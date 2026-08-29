//
//  ModerationService.swift
//  SwiftUIFeatureBugReport
//

import CloudKit
import Foundation
import Observation

/// Developer-only operations. Shipping this in every build is fine - the `dev` security role is what
/// authorises the writes, so a non-developer calling any of it is refused by the server.
@Observable @MainActor public final class ModerationService {

    public var error: FeedbackError?
    public private(set) var isWorking = false

    private let container: FeedbackContainer
    private let requests: RequestService
    private let votes: VoteService
    private let follows: FollowService

    private var database: CKDatabase { container.database }

    public init(container: FeedbackContainer,
                requests: RequestService,
                votes: VoteService,
                follows: FollowService) {

        self.container = container
        self.requests = requests
        self.votes = votes
        self.follows = follows
    }

    // MARK: - Status and labels

    /// Bumps `lastActivityAt` - the author wants a status change to lift a request up the "most
    /// recent" sort (§3.9).
    public func setStatus(_ status: RequestStatus, on request: FeedbackRequest) async {

        // Completing a request prefills the version it shipped in with whatever build the portal is
        // running, which is nearly always right. It stays editable for the case where it is not.
        let version = status == .complete && request.resolvedInVersion.isEmpty
            ? DeviceInfo.getAppVersion()
            : request.resolvedInVersion

        await mutate(request, bumpsActivity: true) { record in

            record[FieldKey.status] = status.rawValue
            record[FieldKey.resolvedInVersion] = version
        }

        let message = String(localized: "Status changed to \(String(localized: statusName(status)))")

        await writeActivity(kind: status == .complete ? .complete : .status,
                            request: request,
                            recipientID: request.creatorID,
                            message: message)
    }

    public func setLabels(_ labels: [String], on request: FeedbackRequest) async {

        await mutate(request, bumpsActivity: true) { record in

            record[FieldKey.labels] = labels
        }
    }

    /// Corrects the shipped-in version on its own.
    ///
    /// Deliberately does **not** bump `lastActivityAt`: fixing a typo in a version string is a
    /// correction, not activity, and it should not lift the request back up the "most recent" sort.
    public func setResolvedVersion(_ version: String, on request: FeedbackRequest) async {

        await mutate(request, bumpsActivity: false) { record in

            record[FieldKey.resolvedInVersion] = version
        }
    }

    // MARK: - Moderation

    /// Hiding does **not** bump `lastActivityAt`. A moderation action is not activity on the request.
    public func hide(_ request: FeedbackRequest) async {

        await mutate(request, bumpsActivity: false) { record in

            record[FieldKey.moderation] = ModerationState.hidden.rawValue
        }
    }

    /// Undoes a manual `hide`, putting the request back under the ordinary rule rather than forcing it
    /// visible.
    ///
    /// Deliberately `visible`, not `approved`: if the request is *also* over the report threshold it
    /// should go straight back to auto-hidden, because that is a separate decision made by users and
    /// unhiding was never a ruling on it. Use `approve` to overrule the reports as well.
    public func unhide(_ request: FeedbackRequest) async {

        await mutate(request, bumpsActivity: false) { record in

            record[FieldKey.moderation] = ModerationState.visible.rawValue
        }
    }

    /// Clearing a report. Moves the request to `approved` rather than back to `visible`, so the
    /// existing reports stop counting - otherwise the threshold is still met and the request re-hides
    /// itself as soon as the next client refreshes.
    public func approve(_ request: FeedbackRequest) async {

        await mutate(request, bumpsActivity: false) { record in

            record[FieldKey.moderation] = ModerationState.approved.rawValue
        }
    }

    public func approveImage(on request: FeedbackRequest) async {

        await mutate(request, bumpsActivity: false) { record in

            record[FieldKey.imageState] = ImageState.approved.rawValue
        }

        await writeActivity(kind: .imageApproved,
                            request: request,
                            recipientID: request.creatorID,
                            message: String(localized: "Your attached image was approved"))
    }

    /// Rejecting **clears every asset**, not just the flag.
    ///
    /// `imageState` gates display, not access: CloudKit has no per-field permissions, so leaving the
    /// bytes in place would keep them fetchable by anyone who queries the record. One state covers the
    /// whole set - a request's images are reviewed together, so there is nothing to reject piecemeal.
    public func rejectImage(on request: FeedbackRequest) async {

        await mutate(request, bumpsActivity: false) { record in

            record[FieldKey.imageState] = ImageState.rejected.rawValue
            record[FieldKey.images] = nil
        }

        await writeActivity(kind: .imageRejected,
                            request: request,
                            recipientID: request.creatorID,
                            message: String(localized: "Your attached image was removed"))
    }

    public func delete(_ request: FeedbackRequest) async {

        isWorking = true

        defer { isWorking = false }

        do {

            _ = try await database.deleteRecord(withID: request.id)

            requests.removeLocally(request.id)
        }
        catch {

            guard !CloudKitErrorHandler.isRecordMissing(error) else {

                requests.removeLocally(request.id)
                return
            }

            self.error = CloudKitErrorHandler.classify(error)
        }
    }

    /// Everything by one author, in one batched delete. Goes through `CloudKitBatch` because a
    /// prolific author is exactly the case where an unsplit batch trips `.limitExceeded`.
    public func hideAll(by authorID: String) async {

        isWorking = true

        defer { isWorking = false }

        let predicate = NSPredicate(format: "%K == %@", FieldKey.creatorID, authorID)
        let query = CKQuery(recordType: RecordType.request, predicate: predicate)

        do {

            // Only `creatorID` is fetched, so these records are partial. That is safe because
            // `CloudKitBatch` saves with `.changedKeys` - an `.allKeys` policy would null out every
            // field that was not fetched.
            let page = try await database.records(matching: query, desiredKeys: [FieldKey.creatorID])

            let records = page.matchResults.compactMap { try? $0.1.get() }

            for record in records { record[FieldKey.moderation] = ModerationState.hidden.rawValue }

            try await CloudKitBatch.save(records, in: database)

            for record in records {

                if let updated = FeedbackRequest(record: record) { requests.replaceLocally(updated) }
            }
        }
        catch {

            self.error = CloudKitErrorHandler.classify(error)
        }
    }

    // MARK: - Notifying

    /// One `Activity` per follower - "shipped in 2.1". Batched, and split on `.limitExceeded`; a
    /// request popular enough to be worth announcing has enough followers to overflow one batch.
    ///
    /// Voters are included alongside explicit followers because voting auto-follows, and votes cast
    /// before following existed have no `Follow` record to find.
    public func notifyFollowers(of request: FeedbackRequest, message: String) async {

        isWorking = true

        defer { isWorking = false }

        let recipients = await follows.recipientIDs(for: request.id)
            .union(await votes.voterIDs(for: request.id))

        let records = recipients.map { recipient in

            activityRecord(kind: .shipped,
                           request: request,
                           recipientID: recipient,
                           message: message,
                           deduplicated: true)
        }

        do {

            try await CloudKitBatch.save(records, in: database)
        }
        catch {

            // Everyone already has this exact announcement, so there is nothing to report.
            guard !CloudKitErrorHandler.isEntirelyDuplicates(error) else { return }

            self.error = CloudKitErrorHandler.classify(error)
        }
    }

    // MARK: - Internals

    private func mutate(_ request: FeedbackRequest,
                        bumpsActivity: Bool,
                        _ changes: (CKRecord) -> Void) async {

        isWorking = true

        defer { isWorking = false }

        do {

            let record = try await database.record(for: request.id)

            changes(record)

            if bumpsActivity { record[FieldKey.lastActivityAt] = Date.now }

            let saved = try await database.save(record)

            requests.replaceLocally(saved)
        }
        catch {

            guard !CloudKitErrorHandler.isRecordMissing(error) else {

                requests.removeLocally(request.id)
                return
            }

            self.error = CloudKitErrorHandler.classify(error)
        }
    }

    /// Every user-visible action writes a matching `Activity` carrying display-ready text.
    private func writeActivity(kind: ActivityKind,
                               request: FeedbackRequest,
                               recipientID: String,
                               message: String) async {

        guard !recipientID.isEmpty else { return }

        do {

            _ = try await database.save(activityRecord(kind: kind,
                                                       request: request,
                                                       recipientID: recipientID,
                                                       message: message))
        }
        catch {

            // Best effort - the status change itself already succeeded, so this must not undo it.
            // But it is surfaced rather than swallowed: a silently failing Activity write means users
            // stop being notified and nothing anywhere says so.
            self.error = CloudKitErrorHandler.classify(error)
        }
    }

    /// Broadcasts get a deterministic record name so the operation can be repeated safely. Per-user
    /// notices keep an auto-generated one: a status can legitimately change more than once, and
    /// collapsing those into a single record would silently swallow the later updates.
    private func activityRecord(kind: ActivityKind,
                                request: FeedbackRequest,
                                recipientID: String,
                                message: String,
                                deduplicated: Bool = false) -> CKRecord {

        let record = deduplicated
            ? CKRecord(recordType: RecordType.activity,
                       recordID: CKRecord.ID(recordName: RecordID.activity(request: request.id.recordName,
                                                                           kind: kind.rawValue,
                                                                           recipient: recipientID,
                                                                           message: message)))
            : CKRecord(recordType: RecordType.activity)

        record[FieldKey.request] = CKRecord.Reference(recordID: request.id, action: .deleteSelf)
        record[FieldKey.recipientID] = recipientID
        record[FieldKey.kind] = kind.rawValue
        record[FieldKey.requestTitle] = request.title
        record[FieldKey.message] = message

        return record
    }

    private func statusName(_ status: RequestStatus) -> String.LocalizationValue {

        switch status {

        case .open: return "Open"
        case .inProgress: return "In Progress"
        case .updatePending: return "Update Pending"
        case .complete: return "Complete"
        }
    }

    // MARK: - Metadata and comment inspection

    /// The private metadata for a request. Only the developer and the request's creator can read it.
    public func metadata(for request: FeedbackRequest) async -> [String: String] {

        let recordID = CKRecord.ID(recordName: RecordID.metadata(request: request.id.recordName))

        guard let record = try? await database.record(for: recordID),
              let metadata = RequestMetadata(record: record) else { return [:] }

        return metadata.values
    }
}
