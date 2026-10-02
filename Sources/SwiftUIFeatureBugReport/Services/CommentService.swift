//
//  CommentService.swift
//  SwiftUIFeatureBugReport
//

import CloudKit
import Foundation
import Observation

@Observable @MainActor public final class CommentService {

    public private(set) var comments: [FeedbackComment] = []
    public private(set) var isLoading = false
    public var error: FeedbackError?

    private let container: FeedbackContainer

    private var database: CKDatabase { container.database }

    public init(container: FeedbackContainer) {

        self.container = container
    }

    /// Loads both record types and merges them into one timeline sorted by creation.
    public func load(for requestID: CKRecord.ID) async {

        isLoading = true
        error = nil

        defer { isLoading = false }

        // With user comments off, the `Comment` record type may not exist in the integrator's schema
        // at all - so do not query it. Developer replies are a separate type and always load.
        //
        // `NSPredicate` is not `Sendable`, so each branch builds its own rather than sharing one
        // across the concurrent calls.
        async let user = container.configuration.allowComments
            ? fetch(recordType: RecordType.comment, on: requestID)
            : []

        async let developer = fetch(recordType: RecordType.devComment, on: requestID)

        let merged = await user + (await developer)

        comments = merged.sorted { $0.createdAt < $1.createdAt }
    }

    private func fetch(recordType: String, on requestID: CKRecord.ID) async -> [FeedbackComment] {

        let reference = CKRecord.Reference(recordID: requestID, action: .none)
        let predicate = NSPredicate(format: "%K == %@", FieldKey.request, reference)

        do {

            let page = try await database.records(matching: CKQuery(recordType: recordType, predicate: predicate))

            return page.matchResults
                .compactMap { try? $0.1.get() }
                .compactMap { FeedbackComment(record: $0) }
        }
        catch {

            if !CloudKitErrorHandler.isRecordMissing(error) {

                self.error = CloudKitErrorHandler.classify(error)
            }

            return []
        }
    }

    /// Whether this user may comment on `request`.
    ///
    /// Only the request's creator and the developer may comment. **CloudKit cannot express "only if
    /// you created the parent record", so this is a client-side rule, not a security boundary.** A
    /// determined user with the CloudKit API could write a `Comment` on any request; the portal
    /// surfaces every comment's `creatorID` so one matching neither the request creator nor a
    /// developer shows up as anomalous.
    public func canComment(on request: FeedbackRequest) -> Bool {

        guard let me = container.currentUserRecordID else { return false }

        // The developer can always reply - turning comments off closes the thread to users, it does
        // not stop you answering someone.
        if container.isDeveloper { return true }

        return container.configuration.allowComments && request.creatorID == me
    }

    /// Posts as the request's creator. Bumps `lastActivityAt` (§3.9).
    public func addUserComment(to request: FeedbackRequest, body: String) async throws {

        guard let me = container.currentUserRecordID else { throw FeedbackError.notSignedIn }

        let record = CKRecord(recordType: RecordType.comment)

        record[FieldKey.request] = CKRecord.Reference(recordID: request.id, action: .deleteSelf)
        record[FieldKey.body] = body
        record[FieldKey.requestCreator] = request.creatorID
        record[FieldKey.creatorID] = me

        try await save(record, bumping: request)
    }

    /// Posts as the developer. `DevComment` is the only record type carrying `dev: CREATE`, which is
    /// what makes developer authorship unforgeable - it is the record type, not a field.
    public func addDeveloperComment(to request: FeedbackRequest, body: String) async throws {

        guard let me = container.currentUserRecordID else { throw FeedbackError.notSignedIn }

        let record = CKRecord(recordType: RecordType.devComment)

        record[FieldKey.request] = CKRecord.Reference(recordID: request.id, action: .deleteSelf)
        record[FieldKey.body] = body
        record[FieldKey.requestCreator] = request.creatorID
        record[FieldKey.creatorID] = me

        try await save(record, bumping: request)

        await writeCommentActivity(for: request, from: me)
    }

    private func save(_ record: CKRecord, bumping request: FeedbackRequest) async throws {

        do {

            let saved = try await database.save(record)

            if let comment = FeedbackComment(record: saved) {

                comments.append(comment)
                comments.sort { $0.createdAt < $1.createdAt }
            }
        }
        catch {

            throw CloudKitErrorHandler.classify(error)
        }

        // A new comment - from either side - counts as activity.
        if let parent = try? await database.record(for: request.id) {

            parent[FieldKey.lastActivityAt] = Date.now

            _ = try? await database.save(parent)
        }
    }

    /// The reply notice addressed to the request's author, which is what the user's
    /// `activity-comment-<user>` subscription has always been waiting for (§8.1).
    ///
    /// Deliberately here rather than in `save(_:bumping:)`, which both comment paths share: `Activity`
    /// grants `CREATE` to `dev` alone, so `addUserComment` cannot write the mirror of this and does
    /// not try. The developer learns about user comments from a subscription on `Comment` instead -
    /// see `ActivityService.registerDeveloperCommentSubscription`.
    ///
    /// The record name is auto-generated rather than composed through `RecordID.activity`: a
    /// deduplicated name is for broadcasts, and a developer may legitimately reply more than once.
    ///
    /// Best effort, and deliberately not thrown. The reply itself already saved, so throwing here
    /// would tell the developer their reply had not posted. The error is surfaced rather than
    /// swallowed, matching `ModerationService.writeActivity`: an `Activity` write that fails quietly
    /// means users stop being notified and nothing anywhere says so.
    private func writeCommentActivity(for request: FeedbackRequest, from me: String) async {

        // Replying to your own test submission should not push to yourself.
        guard !request.creatorID.isEmpty, request.creatorID != me else { return }

        let record = CKRecord(recordType: RecordType.activity)

        record[FieldKey.request] = CKRecord.Reference(recordID: request.id, action: .deleteSelf)
        record[FieldKey.recipientID] = request.creatorID
        record[FieldKey.kind] = ActivityKind.comment.rawValue
        record[FieldKey.requestTitle] = request.title
        record[FieldKey.message] = String(localized: "The developer replied to your request")

        do {

            _ = try await database.save(record)
        }
        catch {

            self.error = CloudKitErrorHandler.classify(error)
        }
    }

    func reset() { comments = [] }
}
