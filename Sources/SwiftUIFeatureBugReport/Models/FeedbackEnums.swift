//
//  FeedbackEnums.swift
//  SwiftUIFeatureBugReport
//

import SwiftUI

/// Every enum here is `String`-backed with an **explicit** `init?(rawValue:)` that falls back to the
/// safe default instead of returning `nil`. A newer client writing a value this build has never heard
/// of must degrade, never crash or vanish from the list.

public enum FeedbackType: String, CaseIterable, Sendable, Hashable {

    case bug
    case feature

    public init?(rawValue: String) {

        switch rawValue {

        case "feature": self = .feature
        default: self = .bug
        }
    }

    public var localised: LocalizedStringKey {

        switch self {

        case .bug: return "Bug"
        case .feature: return "Feature"
        }
    }

    public var symbolName: String {

        switch self {

        case .bug: return "ladybug"
        case .feature: return "lightbulb"
        }
    }
}


public enum RequestStatus: String, CaseIterable, Sendable, Hashable {

    case open
    case inProgress
    case updatePending
    case complete

    public init?(rawValue: String) {

        switch rawValue {

        case "inProgress": self = .inProgress
        case "updatePending": self = .updatePending
        case "complete": self = .complete
        default: self = .open
        }
    }

    public var localised: LocalizedStringKey {

        switch self {

        case .open: return "Open"
        case .inProgress: return "In Progress"
        case .updatePending: return "Update Pending"
        case .complete: return "Complete"
        }
    }

    public var symbolName: String {

        switch self {

        case .open: return "circle"
        case .inProgress: return "hammer"
        case .updatePending: return "arrow.down.circle"
        case .complete: return "checkmark.circle.fill"
        }
    }

    public var tint: Color {

        switch self {

        case .open: return .secondary
        case .inProgress: return .orange
        case .updatePending: return .blue
        case .complete: return .green
        }
    }
}


public enum ModerationState: String, CaseIterable, Sendable, Hashable {

    /// The default. Auto-hides once the report count reaches the configured threshold.
    case visible

    /// A developer looked at the reports and cleared them. Report counts are ignored from here on,
    /// which is what stops a cleared request silently re-hiding itself.
    case approved

    /// Hidden from everyone but the developer.
    case hidden

    public init?(rawValue: String) {

        switch rawValue {

        case "approved": self = .approved
        case "hidden": self = .hidden
        default: self = .visible
        }
    }
}


/// Gates **display, not access.** CloudKit has no per-field permissions, so anyone who can query the
/// record can fetch its asset whatever this says. Rejecting an image therefore also nils the asset -
/// see `ModerationService.rejectImage(on:)`. This is a moderation queue, not a security control.
public enum ImageState: String, CaseIterable, Sendable, Hashable {

    case none
    case pending
    case approved
    case rejected

    public init?(rawValue: String) {

        switch rawValue {

        case "pending": self = .pending
        case "approved": self = .approved
        case "rejected": self = .rejected
        default: self = .none
        }
    }
}


public enum ActivityKind: String, CaseIterable, Sendable, Hashable {

    case status
    case comment
    case complete
    case imageApproved
    case imageRejected
    case shipped

    public init?(rawValue: String) {

        switch rawValue {

        case "comment": self = .comment
        case "complete": self = .complete
        case "imageApproved": self = .imageApproved
        case "imageRejected": self = .imageRejected
        case "shipped": self = .shipped
        default: self = .status
        }
    }

    public var symbolName: String {

        switch self {

        case .status: return "arrow.triangle.2.circlepath"
        case .comment: return "bubble.left"
        case .complete: return "checkmark.circle"
        case .imageApproved: return "photo"
        case .imageRejected: return "photo.badge.exclamationmark"
        case .shipped: return "shippingbox"
        }
    }

    /// The `alertLocalizationKey` used by the push subscription for this kind (§8.1).
    ///
    /// These keys are resolved against the **host app's** bundle, not the package's, so the
    /// integrator has to add them to their own string table. Listed in the README.
    public var localizationKey: String {

        switch self {

        case .status: return "ACTIVITY_STATUS"
        case .comment: return "ACTIVITY_COMMENT"
        case .complete: return "ACTIVITY_COMPLETE"
        case .imageApproved: return "ACTIVITY_IMAGE_APPROVED"
        case .imageRejected: return "ACTIVITY_IMAGE_REJECTED"
        case .shipped: return "ACTIVITY_SHIPPED"
        }
    }
}


public enum BoardSort: String, CaseIterable, Sendable, Hashable {

    case votes
    case mostRecent

    public var localised: LocalizedStringKey {

        switch self {

        case .votes: return "Votes"
        case .mostRecent: return "Most Recent"
        }
    }
}


public enum BoardFilter: String, CaseIterable, Sendable, Hashable {

    case all
    case bugs
    case features

    public var localised: LocalizedStringKey {

        switch self {

        case .all: return "All"
        case .bugs: return "Bugs"
        case .features: return "Features"
        }
    }

    func matches(_ type: FeedbackType) -> Bool {

        switch self {

        case .all: return true
        case .bugs: return type == .bug
        case .features: return type == .feature
        }
    }
}


/// Why something was reported.
///
/// A category rather than free text alone, so the portal's reported queue can be triaged at a glance
/// and the developer is not reading twenty variations of "this is spam". The detail field stays
/// optional alongside it.
public enum ReportCategory: String, CaseIterable, Sendable, Hashable {

    case spam
    case abusive
    case offTopic
    case duplicate
    case other

    public init?(rawValue: String) {

        switch rawValue {

        case "spam": self = .spam
        case "abusive": self = .abusive
        case "offTopic": self = .offTopic
        case "duplicate": self = .duplicate
        default: self = .other
        }
    }

    public var localised: LocalizedStringKey {

        switch self {

        case .spam: return "Spam"
        case .abusive: return "Abusive or offensive"
        case .offTopic: return "Off topic"
        case .duplicate: return "Duplicate"
        case .other: return "Something else"
        }
    }

    /// Plain-`String` form, for places that compose text rather than take a `LocalizedStringKey` -
    /// the portal's "reported as spam (3), off topic (1)" breakdown.
    public var displayName: String {

        switch self {

        case .spam: return String(localized: "Spam")
        case .abusive: return String(localized: "Abusive")
        case .offTopic: return String(localized: "Off topic")
        case .duplicate: return String(localized: "Duplicate")
        case .other: return String(localized: "Other")
        }
    }

    public var symbolName: String {

        switch self {

        case .spam: return "envelope.badge.shield.half.filled"
        case .abusive: return "exclamationmark.bubble"
        case .offTopic: return "arrow.uturn.left"
        case .duplicate: return "doc.on.doc"
        case .other: return "ellipsis.circle"
        }
    }
}


/// Which CloudKit environment a build talks to.
///
/// There is no API that answers this. `CKContainer` does not expose it, and the entitlement that
/// decides it (`com.apple.developer.icloud-container-environment`) is not readable on every platform -
/// on the simulator there is no provisioning profile to inspect at all. So the package does not guess:
/// the integrator states it, and the portal displays what was stated.
///
/// The default is right for the ordinary case - a Debug build talks to Development, a Release build
/// talks to Production. It is wrong only if you deliberately force the entitlement the other way, and
/// that is exactly when you should set this explicitly.
public enum CloudKitEnvironment: String, Sendable, Hashable, CaseIterable {

    case development
    case production

    /// Matches how Xcode configures CloudKit for a normal build. SwiftPM compiles this package with
    /// the host app's configuration, so `DEBUG` here means the app was built for Debug.
    public static var defaultForBuild: CloudKitEnvironment {

        #if DEBUG
        .development
        #else
        .production
        #endif
    }

    public var localised: LocalizedStringKey {

        switch self {

        case .development: return "Development"
        case .production: return "Production"
        }
    }

    /// Development is tinted as a warning: seeing it while you expected live feedback is the mistake
    /// this label exists to catch.
    public var tint: Color {

        switch self {

        case .development: return .orange
        case .production: return .green
        }
    }

    public var symbolName: String {

        switch self {

        case .development: return "hammer.fill"
        case .production: return "checkmark.seal.fill"
        }
    }
}
