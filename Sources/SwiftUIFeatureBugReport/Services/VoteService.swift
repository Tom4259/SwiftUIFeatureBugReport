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

    /// Set when `loadTallies()` stopped early. The partial tallies are still published - a half-loaded
    /// board beats an empty one - but callers can now tell the counts may be low.
    public private(set) var loadError: FeedbackError?

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
        loadError = nil

        defer { isLoading = false }

        var entries: [VoteEntry] = []
        var mine: Set<CKRecord.ID> = []

        let query = CKQuery(recordType: RecordType.vote, predicate: NSPredicate(value: true))
        query.sortDescriptors = [NSSortDescriptor(key: FieldKey.creationDate, ascending: false)]

        let outcome = await CloudKitPaging.forEachPage(
            first: { try await database.records(matching: query, desiredKeys: [FieldKey.request]) },
            next: { (cursor: CKQueryOperation.Cursor) in
                try await database.records(continuingMatchFrom: cursor, desiredKeys: [FieldKey.request])
            },
            body: { matchResults in

                // Count the votes that loaded, but flag the tally as low if any entry failed.
                if let failure = CloudKitErrorHandler.firstMatchFailure(in: matchResults) {

                    loadError = failure
                }

                for (_, result) in matchResults {

                    guard let record = try? result.get(),
                          let entry = VoteEntry(record: record) else { continue }

                    entries.append(entry)

                    if container.isCurrentUser(record.creatorUserRecordID) {

                        mine.insert(entry.request)
                    }
                }
            })

        switch outcome {

        case .finished:
            break

        case .reachedPageCap:
            loadError = CloudKitErrorHandler.incompleteLoad

        case .failed(let error):

            // Keep whatever was counted; a half-loaded tally beats an empty board. Surface it though.
            loadError = CloudKitErrorHandler.classifyQuery(error)
        }

        tallies = Self.distinctTallies(entries)
        myVotes = mine
    }

    /// One vote, reduced to what counting needs.
    struct VoteEntry: Hashable {

        let request: CKRecord.ID
        /// The creator's record name, or - if CloudKit did not return one - the vote's own record name,
        /// so an anonymous row still counts once rather than being dropped.
        let voter: String

        init(request: CKRecord.ID, voter: String) {

            self.request = request
            self.voter = voter
        }

        /// The entry a `Vote` record contributes, or `nil` if it has no request reference.
        init?(record: CKRecord) {

            guard let reference = record[FieldKey.request] as? CKRecord.Reference else { return nil }

            self.init(request: reference.recordID,
                      voter: record.creatorUserRecordID?.recordName ?? record.recordID.recordName)
        }
    }

    /// Counts **distinct voters** per request, not raw `Vote` records.
    ///
    /// The deterministic record name only stops duplicates from well-behaved clients. The schema lets
    /// any iCloud user create `Vote` records, so someone talking to CloudKit directly could save several
    /// under different names. Deduplicating on (request, creator) makes each account count once.
    nonisolated static func distinctTallies(_ entries: [VoteEntry]) -> [CKRecord.ID: Int] {

        var counts: [CKRecord.ID: Int] = [:]

        for entry in Set(entries) {

            counts[entry.request, default: 0] += 1
        }

        return counts
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

        var voters: Set<String> = []

        // Paged like `loadTallies()`: a single page silently dropped voters beyond the first batch.
        // Stopping at the page cap or on a failed page notifies whoever was found so far rather than
        // nobody, and never loops on a continuation that does not end.
        _ = await CloudKitPaging.forEachPage(
            first: { try await database.records(matching: query, desiredKeys: [FieldKey.request]) },
            next: { (cursor: CKQueryOperation.Cursor) in
                try await database.records(continuingMatchFrom: cursor, desiredKeys: [FieldKey.request])
            },
            body: { matchResults in

                for (_, result) in matchResults {

                    if let name = (try? result.get())?.creatorUserRecordID?.recordName { voters.insert(name) }
                }
            })

        return Array(voters)
    }
}
