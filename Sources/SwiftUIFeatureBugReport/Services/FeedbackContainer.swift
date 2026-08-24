//
//  FeedbackContainer.swift
//  SwiftUIFeatureBugReport
//

import CloudKit
import Foundation
import Observation

#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

/// Where the identity resolution has got to.
///
/// Views must not render row-level state until this reaches `.ready`. Rendering earlier means every
/// row reads "not mine, not voted" and then visibly flips a moment later.
public enum IdentityState: Sendable, Equatable {

    case resolving
    case ready
    case noAccount
    case failed(String)
}

/// Owns the `CKContainer` and the signed-in identity. Every other service takes one of these.
@Observable @MainActor public final class FeedbackContainer {

    public let configuration: FeedbackConfiguration

    public private(set) var identityState: IdentityState = .resolving
    public private(set) var currentUserRecordID: String?
    public private(set) var accountStatus: CKAccountStatus = .couldNotDetermine

    /// Gates the portal **UI**. The `dev` security role is what actually enforces developer writes,
    /// so a user who somehow flipped this would still be refused by the server.
    public var isDeveloper: Bool {

        guard let currentUserRecordID else { return false }

        return configuration.developerUserRecordIDs.contains(currentUserRecordID)
    }

    /// Writing to the public database needs a signed-in iCloud account. Reading does not, so this
    /// disables voting and submitting rather than failing the whole screen.
    public var canWrite: Bool { identityState == .ready }

    public let container: CKContainer

    public var database: CKDatabase { container.publicCloudDatabase }

    /// `nonisolated(unsafe)` so `deinit` can unregister. Written once in `init` and read once in
    /// `deinit`, never concurrently.
    @ObservationIgnored private nonisolated(unsafe) var accountObserver: (any NSObjectProtocol)?

    /// Called after `.CKAccountChanged` so dependent services can drop their derived state.
    var onIdentityChange: (@MainActor () -> Void)?

    public init(configuration: FeedbackConfiguration) {

        self.configuration = configuration
        self.container = CKContainer(identifier: configuration.containerIdentifier)

        observeAccountChanges()
    }

    deinit {

        if let accountObserver { NotificationCenter.default.removeObserver(accountObserver) }
    }

    // MARK: - Identity

    public func resolveIdentity() async {

        identityState = .resolving

        do {

            accountStatus = try await container.accountStatus()

            guard accountStatus == .available else {

                currentUserRecordID = nil
                identityState = .noAccount

                return
            }

            let recordID = try await container.userRecordID()

            currentUserRecordID = recordID.recordName
            identityState = .ready
        }
        catch {

            currentUserRecordID = nil

            let feedbackError = CloudKitErrorHandler.classify(error)

            // A missing account is a state, not a failure - the board still reads.
            identityState = feedbackError == .notSignedIn
                ? .noAccount
                : .failed(feedbackError.localizedDescription)
        }
    }

    /// This matters more for a first sign-in, or re-auth after a password change, than for someone
    /// deliberately switching Apple Accounts - but all three land here.
    private func observeAccountChanges() {

        accountObserver = NotificationCenter.default.addObserver(forName: .CKAccountChanged,
                                                                 object: nil,
                                                                 queue: .main) { [weak self] _ in

            // The notification arrives on the main queue, but nothing about `Notification` is Sendable,
            // so hop explicitly rather than capturing it.
            Task { @MainActor [weak self] in

                guard let self else { return }

                await self.resolveIdentity()

                self.onIdentityChange?()
            }
        }
    }

    /// Whether a record's creator is this user.
    ///
    /// CloudKit does **not** stamp your own actual user record ID onto records you created - it
    /// returns `CKCurrentUserDefaultName` ("__defaultOwner__") instead. Comparing straight against
    /// `currentUserRecordID` therefore never matches your own records, which silently made every
    /// "is this mine?" check say no: your votes read as unvoted, your follows as unfollowed, and
    /// content you reported came back after a reload.
    public func isCurrentUser(_ recordID: CKRecord.ID?) -> Bool {

        guard let recordID else { return false }

        if recordID.recordName == CKCurrentUserDefaultName { return true }

        return recordID.recordName == currentUserRecordID
    }

    // MARK: - Push registration

    /// Platform split only - the rest of the subscription work is identical (§8.4).
    public func registerForRemoteNotifications() {

        #if os(iOS) || targetEnvironment(macCatalyst)
        UIApplication.shared.registerForRemoteNotifications()
        #elseif os(macOS)
        NSApplication.shared.registerForRemoteNotifications()
        #endif
    }
}


extension FeedbackError: Equatable {

    public static func == (lhs: FeedbackError, rhs: FeedbackError) -> Bool {

        lhs.localizedDescription == rhs.localizedDescription
    }
}
