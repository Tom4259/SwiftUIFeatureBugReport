//
//  FeedbackConfiguration.swift
//  SwiftUIFeatureBugReport
//

import Foundation

/// Everything the package needs from the integrating app.
///
/// Each integrator runs this on their **own** CloudKit container under their own Apple Developer
/// account - the package ships no credentials and the package author receives no data.
public struct FeedbackConfiguration: Sendable {

    /// e.g. `iCloud.com.yourcompany.yourapp`. Must also be listed in the app target's iCloud capability.
    public let containerIdentifier: String

    /// CloudKit user record IDs (`_abc123...`) that should see the developer portal.
    ///
    /// A list rather than a single constant so a team can have more than one developer, and so a
    /// developer can add a second Apple Account without shipping an update.
    ///
    /// This gates the portal **UI only**. The `dev` security role in the CloudKit Dashboard is what
    /// actually authorises developer writes, so shipping the portal in every build is not a hole.
    public let developerUserRecordIDs: [String]

    /// Number of reports at which a `visible` request auto-hides for everyone. See `ReportService`.
    public let reportThreshold: Int

    /// Whether users may reply on their own requests.
    ///
    /// Turning this off is a real decision, not a cosmetic one: every reply is a message someone
    /// expects an answer to. Developer replies are unaffected - a user can still be answered, they
    /// just cannot start a thread.
    ///
    /// **This is a UI convention, not a security boundary.** CloudKit cannot express "only the request
    /// creator may comment", so a determined user could still write a `Comment` record directly. To
    /// make it enforced, omit the `Comment` record type from your schema entirely - see the README.
    /// When it is `false` the package never queries that record type, so leaving it out is safe.
    public let allowComments: Bool

    /// Whether users may attach screenshots.
    ///
    /// Images are the bulk of a public container's storage, and accepting user-submitted pictures
    /// raises the moderation bar considerably. Text-only is a legitimate choice. Images already
    /// attached before this was turned off still display.
    public let allowImageAttachments: Bool

    /// Which CloudKit environment this build talks to. Displayed in the developer portal.
    ///
    /// Purely a label - it does not change which environment CloudKit uses, because nothing in the app
    /// can. Set it to whatever your build actually targets so the portal cannot quietly show you
    /// Development data while you believe you are moderating live feedback.
    ///
    /// Override the default if you force `com.apple.developer.icloud-container-environment`:
    ///
    /// ```swift
    /// #if PRODUCTION_CLOUDKIT
    /// environment: .production
    /// #else
    /// environment: .development
    /// #endif
    /// ```
    public let environment: CloudKitEnvironment

    public init(containerIdentifier: String,
                developerUserRecordIDs: [String] = [],
                reportThreshold: Int = 3,
                allowComments: Bool = true,
                allowImageAttachments: Bool = true,
                environment: CloudKitEnvironment = .defaultForBuild) {

        self.containerIdentifier = containerIdentifier
        self.developerUserRecordIDs = developerUserRecordIDs
        self.reportThreshold = reportThreshold
        self.allowComments = allowComments
        self.allowImageAttachments = allowImageAttachments
        self.environment = environment
    }

}
