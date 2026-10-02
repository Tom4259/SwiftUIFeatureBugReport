//
//  ActivityService.swift
//  SwiftUIFeatureBugReport
//

import CloudKit
import Foundation
import Observation
import UserNotifications

@Observable @MainActor public final class ActivityService {

    public private(set) var activity: [FeedbackActivity] = []
    public private(set) var isLoading = false
    public var error: FeedbackError?

    private let container: FeedbackContainer

    private var database: CKDatabase { container.database }

    /// The whole of the local unread bookkeeping: one date.
    ///
    /// Deliberately not a per-request count. Counts kept locally go stale in both directions - a
    /// reinstall marks every thread unread, and a deleted request leaves a key behind forever - while
    /// a single high-water mark survives both.
    private static let lastSeenKey = "com.swiftuifeaturebugreport.lastSeenActivityDate"

    /// The observable half of `lastSeenActivityDate`. Read from `UserDefaults` once, at init.
    private var lastSeen: Date

    /// Backed by stored state rather than reading `UserDefaults` on every get, because the board's
    /// unread badge observes this.
    ///
    /// A property computed straight off `UserDefaults` mutates nothing `@Observable` can see, so
    /// `markAllSeen()` changed what `unreadCount` returns without telling SwiftUI - and the badge
    /// cleared only when something unrelated happened to re-render the board, which is worse than not
    /// clearing at all. Going through a stored property makes the write observable; writing through on
    /// every set keeps the persistence exactly as it was.
    public var lastSeenActivityDate: Date {

        get { lastSeen }
        set {

            lastSeen = newValue
            UserDefaults.standard.set(newValue, forKey: Self.lastSeenKey)
        }
    }

    public var unreadCount: Int {

        let lastSeen = lastSeenActivityDate

        return activity.filter { $0.createdAt > lastSeen }.count
    }

    public init(container: FeedbackContainer) {

        self.container = container
        self.lastSeen = UserDefaults.standard.object(forKey: Self.lastSeenKey) as? Date ?? .distantPast
    }

    func reset() { activity = [] }

    public func markAllSeen() { lastSeenActivityDate = .now }

    /// Everything addressed to this user. Pure client-side query - no subscriptions required, no
    /// setup step, works the first time the app is opened after an update.
    public func feed() async {

        guard let me = container.currentUserRecordID else {

            activity = []
            return
        }

        isLoading = true
        error = nil

        defer { isLoading = false }

        let predicate = NSPredicate(format: "%K == %@", FieldKey.recipientID, me)
        let query = CKQuery(recordType: RecordType.activity, predicate: predicate)

        query.sortDescriptors = [NSSortDescriptor(key: FieldKey.creationDate, ascending: false)]

        do {

            let page = try await database.records(matching: query, resultsLimit: 100)

            activity = page.matchResults
                .compactMap { try? $0.1.get() }
                .compactMap { FeedbackActivity(record: $0) }
        }
        catch {

            self.error = CloudKitErrorHandler.classify(error)
        }
    }

    // MARK: - Notification permission

    /// APNs registration is required on every launch, but it must not trigger the permission prompt.
    /// The prompt remains tied to the first submission below.
    public func registerForRemoteNotificationsIfAuthorized() async {

        let status = await UNUserNotificationCenter.current().notificationSettings().authorizationStatus

        if status == .authorized || status == .provisional {

            container.registerForRemoteNotifications()
        }
    }

    /// Asked **at the moment the user submits their first request**, never on first open of the board
    /// (§8.3). There is exactly one system prompt available per install and asking cold wastes it.
    @discardableResult public func requestNotificationAuthorization() async -> Bool {

        let centre = UNUserNotificationCenter.current()

        let settings = await centre.notificationSettings()

        guard settings.authorizationStatus == .notDetermined else {

            let isAuthorized = settings.authorizationStatus == .authorized
                || settings.authorizationStatus == .provisional

            // APNs registration is per launch, not per permission prompt. The user may have granted
            // permission in an earlier run, so register again whenever notifications remain enabled.
            if isAuthorized { container.registerForRemoteNotifications() }

            return isAuthorized
        }

        do {

            let granted = try await centre.requestAuthorization(options: [.alert, .sound, .badge])

            if granted { container.registerForRemoteNotifications() }

            return granted
        }
        catch {

            return false
        }
    }

    // MARK: - Subscriptions

    /// The activity push's title line: the triggering request's own title, and nothing around it.
    ///
    /// The key is the bare format string because there is no English in this line to translate - the one
    /// thing it carries is a title the user typed themselves. A host app that wants something around it
    /// adds `"%@" = "Update: %@";` to its own catalogue.
    ///
    /// `nonisolated`, like the two below, because it is a constant rather than state: nothing about it
    /// belongs to the main actor, and the tests read it from a plain test function.
    nonisolated static let activityTitleFormat = "%@"

    /// One subscription per `kind` (§8.1).
    ///
    /// `CKSubscription.NotificationInfo` is fixed **when the subscription is created**, not per event,
    /// so a literal `alertBody` would be identical forever. Dynamic text has to come from
    /// `alertLocalizationKey` plus `alertLocalizationArgs`, where the args are **field names** and
    /// CloudKit substitutes their values from the triggering record server-side.
    ///
    /// Every key here is its own en-GB source string rather than a token like `ACTIVITY_COMMENT`. Keys
    /// resolve against the host app's bundle and a missing one is shown verbatim, so the tokens were
    /// arriving on screen as machine text in any app that had not copied them into a catalogue. English
    /// keys make that fallback harmless and still leave the strings translatable by the integrator.
    ///
    /// The status value itself is deliberately kept out of the push: one subscription means one format
    /// string, and pushing a raw value like `updatePending` through `%@` leaks machine strings into
    /// user-visible text. The user taps through for the detail.
    public func registerSubscriptions() async {

        guard let me = container.currentUserRecordID else { return }

        for kind in ActivityKind.allCases {

            let predicate = NSPredicate(format: "%K == %@ AND %K == %@",
                                        FieldKey.recipientID, me,
                                        FieldKey.kind, kind.rawValue)

            let subscription = CKQuerySubscription(recordType: RecordType.activity,
                                                   predicate: predicate,
                                                   subscriptionID: "activity-\(kind.rawValue)-\(me)",
                                                   options: [.firesOnRecordCreation])

            let info = CKSubscription.NotificationInfo()

            info.titleLocalizationKey = Self.activityTitleFormat
            info.titleLocalizationArgs = [FieldKey.requestTitle]
            info.alertLocalizationKey = kind.localizationKey
            info.shouldSendContentAvailable = true
            info.desiredKeys = [FieldKey.request, FieldKey.kind, FieldKey.message]
            info.soundName = "default"

            subscription.notificationInfo = info

            await save(subscription)
        }
    }

    /// The two lines of the developer's new-request push, in en-GB.
    ///
    /// Neither takes an argument: the request's own title is not pushed, because one subscription means
    /// one fixed format string and the portal queue is a tap away. That leaves them as plain sentences an
    /// integrator can translate, or leave exactly as they read here.
    nonisolated static let developerNotificationTitle = "New request"
    nonisolated static let developerNotificationBody = "A user created a new request."

    /// Fires when anyone *else* creates a request (§8.2). The `creatorID != me` clause is what stops
    /// the developer being notified of their own test submissions.
    ///
    /// Sent as localization keys whose keys are the English sentences above, the same convention as the
    /// activity subscriptions. This notification used to push `ACTIVITY_TITLE` and `NEW_REQUEST`, which
    /// is what a developer saw on the lock screen unless they had copied both tokens into their app's
    /// catalogue. An English key shown verbatim is already the notification.
    public func registerDeveloperSubscription() async {

        guard container.isDeveloper, let me = container.currentUserRecordID else { return }

        let predicate = NSPredicate(format: "%K != %@", FieldKey.creatorID, me)

        let subscription = CKQuerySubscription(recordType: RecordType.request,
                                               predicate: predicate,
                                               subscriptionID: "developer-new-request-\(me)",
                                               options: [.firesOnRecordCreation])

        let info = CKSubscription.NotificationInfo()

        info.titleLocalizationKey = Self.developerNotificationTitle
        info.alertLocalizationKey = Self.developerNotificationBody
        info.shouldSendContentAvailable = true
        info.desiredKeys = [FieldKey.title, FieldKey.type]
        info.soundName = "default"

        subscription.notificationInfo = info

        await save(subscription)
    }

    /// The two lines of the developer's new-comment push, in en-GB.
    nonisolated static let developerCommentTitle = "New comment"
    nonisolated static let developerCommentBody = "A user commented on a request."

    /// Fires when anyone *else* writes a `Comment` - the developer's half of a comment thread, in the
    /// same shape as the new-request subscription above.
    ///
    /// A subscription on `Comment` rather than an `Activity` written by the commenter, because
    /// `Activity` grants `CREATE` to `dev` alone. Widening that to `_icloud` would let any client pick
    /// its own `recipientID` and `requestTitle` - and `requestTitle` is the value the activity push
    /// substitutes into its **title line**. Since `creatorID` is world-readable and queryable on
    /// `Request`, recipients are discoverable, so that grant would turn the push channel into an
    /// arbitrary-text relay to any user. The grant stays as it is and the developer's own device does
    /// the watching instead. `Comment.creatorID` is already `QUERYABLE`, so this needs no schema change.
    ///
    /// No `Activity` record is written, so this does not appear in the developer's Updates feed. That
    /// matches the new-request notification: the portal queue is the developer's durable view, and the
    /// push is only the nudge to go and look.
    ///
    /// Guarded on `allowComments` because the `Comment` record type does not exist at all in the
    /// comments-off schema, the same reason `CommentService.load` refuses to query it.
    public func registerDeveloperCommentSubscription() async {

        guard container.isDeveloper,
              container.configuration.allowComments,
              let me = container.currentUserRecordID else { return }

        let predicate = NSPredicate(format: "%K != %@", FieldKey.creatorID, me)

        let subscription = CKQuerySubscription(recordType: RecordType.comment,
                                               predicate: predicate,
                                               subscriptionID: "developer-new-comment-\(me)",
                                               options: [.firesOnRecordCreation])

        let info = CKSubscription.NotificationInfo()

        info.titleLocalizationKey = Self.developerCommentTitle
        info.alertLocalizationKey = Self.developerCommentBody
        info.shouldSendContentAvailable = true
        info.desiredKeys = [FieldKey.request, FieldKey.creatorID]
        info.soundName = "default"

        subscription.notificationInfo = info

        await save(subscription)
    }

    /// Subscriptions are per-environment (development and production are separate) and tied to the
    /// iCloud account, so they vanish on reinstall and have to be re-registered every launch. Saving
    /// one that already exists is therefore the *expected* outcome, not a failure.
    private func save(_ subscription: CKQuerySubscription) async {

        do {

            _ = try await database.save(subscription)
        }
        catch {

            // Surface only the misconfiguration case; everything else here is noise.
            if CloudKitErrorHandler.classify(error) == .developerRoleNotConfigured {

                self.error = .developerRoleNotConfigured
            }
        }
    }
}
