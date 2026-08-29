//
//  VoteService.swift
//  SwiftUIFeatureBugReport
//

import CloudKit
import Foundation
import Observation

@Observable @MainActor public final class VoteService {

    public private(set) var tallies: [CKRecord.ID: Int] = [:]

    /// Derived from the same query as `tallies`, by filtering on creator.
    ///
    /// **There is no local persistence of vote state at all** - no `UserDefaults`, no `@AppStorage`,
    /// no runtime bookkeeping beyond this set. Vote state held on the device is a second vote waiting
    /// to happen: a reinstall would hand the user another, and a second device another still. The
    /// server is the only record of who voted.
    public private(set) var myVotes: Set<CKRecord.ID> = []

    public private(set) var isLoading = false

    private let container: FeedbackContainer

    private var database: CKDatabase { container.database }

    public init(container: FeedbackContainer) {

        self.container = container
    }

    func reset() {

        tallies = [:]
        myVotes = []
    }

    public func tally(for requestID: CKRecord.ID) -> Int { tallies[requestID] ?? 0 }

    public func hasVoted(on requestID: CKRecord.ID) -> Bool { myVotes.contains(requestID) }

    /// **One** query over all `Vote` records, grouped client-side. Not one query per request.
    ///
    /// CloudKit has no COUNT and no atomic increment, so counting votes means reading the vote
    /// records. `desiredKeys = ["request"]` keeps each row to a single reference, which is what makes
    /// this affordable at board scale.
    public func loadTallies() async {

        isLoading = true

        defer { isLoading = false }

        var counts: [CKRecord.ID: Int] = [:]
        var mine: Set<CKRecord.ID> = []

        let query = CKQuery(recordType: RecordType.vote, predicate: NSPredicate(value: true))
        query.sortDescriptors = [NSSortDescriptor(key: FieldKey.creationDate, ascending: false)]

        var cursor: CKQueryOperation.Cursor?

        repeat {

            do {

                let page: (matchResults: [(CKRecord.ID, Result<CKRecord, any Error>)], queryCursor: CKQueryOperation.Cursor?)

                if let cursor {

                    page = try await database.records(continuingMatchFrom: cursor, desiredKeys: [FieldKey.request])
                }
                else {

                    page = try await database.records(matching: query, desiredKeys: [FieldKey.request])
                }

                for (_, result) in page.matchResults {

                    guard let record = try? result.get(),
                          let reference = record[FieldKey.request] as? CKRecord.Reference else { continue }

                    counts[reference.recordID, default: 0] += 1

                    if container.isCurrentUser(record.creatorUserRecordID) {

                        mine.insert(reference.recordID)
                    }
                }

                cursor = page.queryCursor
            }
            catch {

                // Keep whatever was counted; a half-loaded tally beats an empty board.
                break
            }
        }
        while cursor != nil

        tallies = counts
        myVotes = mine
    }

    /// Saves with the deterministic record name from §4.
    ///
    /// A duplicate failure means the user had already voted - from another device, or before a
    /// reinstall - so it resolves to "voted", not to an error.
    public func vote(on requestID: CKRecord.ID) async throws {

        guard let me = container.currentUserRecordID else { throw FeedbackError.notSignedIn }

        guard !myVotes.contains(requestID) else { return }

        let recordID = CKRecord.ID(recordName: RecordID.vote(request: requestID.recordName, user: me))
        let record = CKRecord(recordType: RecordType.vote, recordID: recordID)

        record[FieldKey.request] = CKRecord.Reference(recordID: requestID, action: .deleteSelf)

        do {

            _ = try await database.save(record)

            tallies[requestID, default: 0] += 1
            myVotes.insert(requestID)
        }
        catch {

            if CloudKitErrorHandler.isDuplicateRecord(error) {

                // Already voted. Reconcile the UI, show nothing.
                myVotes.insert(requestID)

                if tallies[requestID] == nil { tallies[requestID] = 1 }

                return
            }

            throw CloudKitErrorHandler.classify(error)
        }
    }

    /// Withdraws a vote.
    ///
    /// Possible because `Vote` grants WRITE to `_creator`. Deliberately a withdrawal and not a
    /// downvote: a signed tally would leave "0" meaning both "nobody asked" and "opinion is split",
    /// which is strictly less useful for deciding what to build, and it would make the edit lock's
    /// "has another user voted" question unanswerable.
    public func unvote(on requestID: CKRecord.ID) async throws {

        guard let me = container.currentUserRecordID else { throw FeedbackError.notSignedIn }

        guard myVotes.contains(requestID) else { return }

        let recordID = CKRecord.ID(recordName: RecordID.vote(request: requestID.recordName, user: me))

        do {

            _ = try await database.deleteRecord(withID: recordID)
        }
        catch {

            // Already gone is the outcome we wanted.
            guard CloudKitErrorHandler.isRecordMissing(error) else { throw CloudKitErrorHandler.classify(error) }
        }

        myVotes.remove(requestID)
        tallies[requestID] = max(0, (tallies[requestID] ?? 1) - 1)
    }

    /// Everyone who voted on a request, for "shipped in x" notifications (§6.7).
    func voterIDs(for requestID: CKRecord.ID) async -> [String] {

        let reference = CKRecord.Reference(recordID: requestID, action: .none)
        let predicate = NSPredicate(format: "%K == %@", FieldKey.request, reference)

        let query = CKQuery(recordType: RecordType.vote, predicate: predicate)

        do {

            let page = try await database.records(matching: query, desiredKeys: [FieldKey.request])

            return page.matchResults
                .compactMap { try? $0.1.get() }
                .compactMap { $0.creatorUserRecordID?.recordName }
        }
        catch {

            return []
        }
    }
}
