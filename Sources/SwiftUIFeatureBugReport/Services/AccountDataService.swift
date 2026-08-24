//
//  AccountDataService.swift
//  SwiftUIFeatureBugReport
//

import CloudKit
import Foundation
import Observation

/// Counts shown before the destructive action, so the confirmation says what is actually at stake.
public struct MyDataCounts: Sendable, Equatable {

    public var requests = 0
    public var votes = 0
    public var comments = 0
    public var reports = 0

    public var isEmpty: Bool { requests == 0 && votes == 0 && comments == 0 && reports == 0 }
}

@Observable @MainActor public final class AccountDataService {

    public private(set) var counts = MyDataCounts()
    public private(set) var isLoading = false
    public private(set) var isDeleting = false
    public var error: FeedbackError?

    private let container: FeedbackContainer

    private var database: CKDatabase { container.database }

    public init(container: FeedbackContainer) {

        self.container = container
    }

    public func loadCounts() async {

        guard let me = container.currentUserRecordID else { return }

        isLoading = true
        error = nil

        defer { isLoading = false }

        async let requests = recordIDs(ofType: RecordType.request, createdBy: me).count
        async let votes = recordIDs(ofType: RecordType.vote, createdBy: me).count
        async let comments = recordIDs(ofType: RecordType.comment, createdBy: me).count
        async let reports = recordIDs(ofType: RecordType.report, createdBy: me).count

        counts = MyDataCounts(requests: await requests,
                              votes: await votes,
                              comments: await comments,
                              reports: await reports)
    }

    /// Real deletion (§6.8).
    ///
    /// Deleting a request takes other people's votes and comments on it with it, because every child
    /// reference uses `.deleteSelf`. That is the intended behaviour - the point is honouring the
    /// request - and the confirmation dialog states it plainly rather than burying it.
    ///
    /// **Votes this user cast on other people's requests are deliberately left in place.** A vote is
    /// a bare reference with no content of its own, and removing them would silently rewrite other
    /// people's tallies. Free text the user wrote - their requests, replies and reports - all goes.
    /// Anyone who wants a specific vote gone can withdraw it from the request itself.
    public func deleteAllMyData() async {

        guard let me = container.currentUserRecordID else {

            error = .notSignedIn
            return
        }

        await delete(creatorID: me)
    }

    /// The same operation the portal offers, keyed by `creatorID`, so a developer can act on a
    /// deletion request that arrived by email.
    public func delete(creatorID: String) async {

        isDeleting = true
        error = nil

        defer { isDeleting = false }

        do {

            // Requests first: `.deleteSelf` cascades their votes, comments, reports, activity and
            // metadata, so the later passes have less to do.
            try await CloudKitBatch.delete(await recordIDs(ofType: RecordType.request, createdBy: creatorID), in: database)

            // Then the text this user left on *other people's* requests. Votes are not in this list -
            // see the note above.
            try await CloudKitBatch.delete(await recordIDs(ofType: RecordType.comment, createdBy: creatorID), in: database)
            try await CloudKitBatch.delete(await recordIDs(ofType: RecordType.report, createdBy: creatorID), in: database)

            counts = MyDataCounts(requests: 0,
                                  votes: await recordIDs(ofType: RecordType.vote, createdBy: creatorID).count,
                                  comments: 0,
                                  reports: 0)
        }
        catch {

            self.error = CloudKitErrorHandler.classify(error)
        }
    }

    /// Queried by CloudKit's own creator reference rather than by our denormalised `creatorID`, so it
    /// also catches record types that have no such field.
    private func recordIDs(ofType recordType: String, createdBy userRecordName: String) async -> [CKRecord.ID] {

        let reference = CKRecord.Reference(recordID: CKRecord.ID(recordName: userRecordName), action: .none)
        let predicate = NSPredicate(format: "creatorUserRecordID == %@", reference)

        var collected: [CKRecord.ID] = []
        var cursor: CKQueryOperation.Cursor?

        repeat {

            do {

                let page: (matchResults: [(CKRecord.ID, Result<CKRecord, any Error>)], queryCursor: CKQueryOperation.Cursor?)

                if let cursor {

                    page = try await database.records(continuingMatchFrom: cursor, desiredKeys: [])
                }
                else {

                    page = try await database.records(matching: CKQuery(recordType: recordType, predicate: predicate),
                                                      desiredKeys: [])
                }

                collected.append(contentsOf: page.matchResults.map { $0.0 })

                cursor = page.queryCursor
            }
            catch {

                self.error = CloudKitErrorHandler.classify(error)
                break
            }
        }
        while cursor != nil

        return collected
    }
}
