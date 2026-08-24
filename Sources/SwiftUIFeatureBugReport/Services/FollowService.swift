//
//  FollowService.swift
//  SwiftUIFeatureBugReport
//

import CloudKit
import Foundation
import Observation

/// Following separates "tell me when this changes" from "I want this built".
///
/// Voting used to be the only way to hear about a request, which forced anyone tracking a bug they
/// had not personally asked for to inflate its tally to do so. Voting still follows automatically -
/// that is the common case - but the two can now come apart.
@Observable @MainActor public final class FollowService {

    public private(set) var myFollows: Set<CKRecord.ID> = []

    private let container: FeedbackContainer

    private var database: CKDatabase { container.database }

    public init(container: FeedbackContainer) {

        self.container = container
    }

    func reset() { myFollows = [] }

    public func isFollowing(_ requestID: CKRecord.ID) -> Bool { myFollows.contains(requestID) }

    /// One bulk query, same shape as votes and reports: `desiredKeys = ["request"]`, filtered on
    /// creator client-side. No local persistence.
    public func loadMyFollows() async {

        guard container.currentUserRecordID != nil else {

            myFollows = []
            return
        }

        var mine: Set<CKRecord.ID> = []

        let query = CKQuery(recordType: RecordType.follow, predicate: NSPredicate(value: true))

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
                          let reference = record[FieldKey.request] as? CKRecord.Reference,
                          container.isCurrentUser(record.creatorUserRecordID) else { continue }

                    mine.insert(reference.recordID)
                }

                cursor = page.queryCursor
            }
            catch {

                break
            }
        }
        while cursor != nil

        myFollows = mine
    }

    /// Deterministic record name, so a duplicate save means "already following" rather than an error -
    /// the same mechanism votes and reports use.
    public func follow(_ requestID: CKRecord.ID) async throws {

        guard let me = container.currentUserRecordID else { throw FeedbackError.notSignedIn }

        guard !myFollows.contains(requestID) else { return }

        let recordID = CKRecord.ID(recordName: RecordID.follow(request: requestID.recordName, user: me))
        let record = CKRecord(recordType: RecordType.follow, recordID: recordID)

        record[FieldKey.request] = CKRecord.Reference(recordID: requestID, action: .deleteSelf)

        do {

            _ = try await database.save(record)

            myFollows.insert(requestID)
        }
        catch {

            guard CloudKitErrorHandler.isDuplicateRecord(error) else { throw CloudKitErrorHandler.classify(error) }

            myFollows.insert(requestID)
        }
    }

    public func unfollow(_ requestID: CKRecord.ID) async throws {

        guard let me = container.currentUserRecordID else { throw FeedbackError.notSignedIn }

        guard myFollows.contains(requestID) else { return }

        let recordID = CKRecord.ID(recordName: RecordID.follow(request: requestID.recordName, user: me))

        do {

            _ = try await database.deleteRecord(withID: recordID)
        }
        catch {

            guard CloudKitErrorHandler.isRecordMissing(error) else { throw CloudKitErrorHandler.classify(error) }
        }

        myFollows.remove(requestID)
    }

    /// Everyone to notify about a request: its followers plus its voters, de-duplicated.
    ///
    /// Voters are included because voting auto-follows, and a vote cast before this record type
    /// existed has no matching `Follow` to find.
    func recipientIDs(for requestID: CKRecord.ID) async -> Set<String> {

        let reference = CKRecord.Reference(recordID: requestID, action: .none)
        let predicate = NSPredicate(format: "%K == %@", FieldKey.request, reference)

        do {

            let page = try await database.records(matching: CKQuery(recordType: RecordType.follow, predicate: predicate),
                                                  desiredKeys: [FieldKey.request])

            return Set(page.matchResults
                .compactMap { try? $0.1.get() }
                .compactMap { $0.creatorUserRecordID?.recordName })
        }
        catch {

            return []
        }
    }
}
