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
    /// v1 stored a comment count per issue, which meant a reinstall marked every thread unread and a
    /// deleted issue left a stale key behind forever.
    private let lastSeenKey = "com.swiftuifeaturebugreport.lastSeenActivityDate"

    public var lastSeenActivityDate: Date {

        get { UserDefaults.standard.object(forKey: lastSeenKey) as? Date ?? .distantPast }
        set { UserDefaults.standard.set(newValue, forKey: lastSeenKey) }
    }

    public var unreadCount: Int {

        let lastSeen = lastSeenActivityDate

        return activity.filter { $0.createdAt > lastSeen }.count
    }

    public init(container: FeedbackContainer) {

        self.container = container
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

    /// Asked **at the moment the user submits their first request**, never on first open of the board
    /// (§8.3). There is exactly one system prompt available per install and asking cold wastes it.
    @discardableResult public func requestNotificationAuthorization() async -> Bool {

        let centre = UNUserNotificationCenter.current()

        let settings = await centre.notificationSettings()

        guard settings.authorizationStatus == .notDetermined else {

            return settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional
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

    /// One subscription per `kind` (§8.1).
    ///
    /// `CKSubscription.NotificationInfo` is fixed **when the subscription is created**, not per event,
    /// so a literal `alertBody` would be identical forever. Dynamic text has to come from
    /// `alertLocalizationKey` plus `alertLocalizationArgs`, where the args are **field names** and
    /// CloudKit substitutes their values from the triggering record server-side.
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

            info.titleLocalizationKey = "ACTIVITY_TITLE"
            info.titleLocalizationArgs = [FieldKey.requestTitle]
            info.alertLocalizationKey = kind.localizationKey
            info.alertLocalizationArgs = [FieldKey.requestTitle]
            info.shouldSendContentAvailable = true
            info.desiredKeys = [FieldKey.request, FieldKey.kind, FieldKey.message]
            info.soundName = "default"

            subscription.notificationInfo = info

            await save(subscription)
        }
    }

    /// Fires when anyone *else* creates a request (§8.2). The `creatorID != me` clause is what stops
    /// the developer being notified of their own test submissions.
    public func registerDeveloperSubscription() async {

        guard container.isDeveloper, let me = container.currentUserRecordID else { return }

        let predicate = NSPredicate(format: "%K != %@", FieldKey.creatorID, me)

        let subscription = CKQuerySubscription(recordType: RecordType.request,
                                               predicate: predicate,
                                               subscriptionID: "developer-new-request-\(me)",
                                               options: [.firesOnRecordCreation])

        let info = CKSubscription.NotificationInfo()

        info.titleLocalizationKey = "ACTIVITY_TITLE"
        info.titleLocalizationArgs = [FieldKey.title]
        info.alertLocalizationKey = "NEW_REQUEST"
        info.alertLocalizationArgs = [FieldKey.title]
        info.shouldSendContentAvailable = true
        info.desiredKeys = [FieldKey.title, FieldKey.type]
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
