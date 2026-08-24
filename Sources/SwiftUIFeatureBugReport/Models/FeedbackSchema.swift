//
//  FeedbackSchema.swift
//  SwiftUIFeatureBugReport
//

import Foundation

/// Record type names and field keys, in one place so a rename is a compile error rather than a
/// runtime miss. These strings must match `Schema.ckdb` exactly.
enum RecordType {

    static let request = "Request"
    static let vote = "Vote"
    static let report = "Report"
    static let comment = "Comment"
    static let devComment = "DevComment"
    static let activity = "Activity"
    static let follow = "Follow"
    static let requestMetadata = "RequestMetadata"
}


enum FieldKey {

    // Request
    static let title = "title"
    static let body = "body"
    static let type = "type"
    static let status = "status"
    static let moderation = "moderation"
    static let imageState = "imageState"
    static let labels = "labels"
    static let images = "images"
    static let creatorID = "creatorID"
    static let appVersion = "appVersion"
    static let osVersion = "osVersion"
    static let deviceModel = "deviceModel"
    static let platform = "platform"

    /// The version a request was **fixed** in. Distinct from `appVersion`, which is the version it was
    /// **reported** from.
    static let resolvedInVersion = "resolvedInVersion"
    static let buildNumber = "buildNumber"
    static let lastActivityAt = "lastActivityAt"

    // Vote / Report / Comment / Activity / RequestMetadata
    static let request = "request"
    static let reason = "reason"
    static let category = "category"
    static let requestCreator = "requestCreator"
    static let recipientID = "recipientID"
    static let kind = "kind"
    static let requestTitle = "requestTitle"
    static let message = "message"
    static let payload = "payload"

    /// CloudKit's own creation timestamp, as addressed from an `NSSortDescriptor`. The matching
    /// Dashboard index is listed as `createdTimestamp` on the record type - the two names refer to the
    /// same system field.
    static let creationDate = "creationDate"
}


/// Deterministic record names (§4).
///
/// CloudKit has no unique constraints. Composing the record name from the request and the user is
/// the **only** thing enforcing one-vote-per-user and one-report-per-user: a second save with the
/// same name fails server-side, and that failure is the mechanism.
enum RecordID {

    static func vote(request: String, user: String) -> String { validated("vote_\(request)_\(user)") }

    static func report(request: String, user: String) -> String { validated("report_\(request)_\(user)") }

    static func follow(request: String, user: String) -> String { validated("follow_\(request)_\(user)") }

    static func metadata(request: String) -> String { validated("meta_\(request)") }

    /// Makes a broadcast repeatable. Announcing the same thing twice - a double-tapped "Notify
    /// everyone following" - collides server-side instead of sending everyone a second push.
    ///
    /// The message is part of the key, so a *different* announcement on the same request still gets
    /// through. Only an identical one is suppressed.
    static func activity(request: String, kind: String, recipient: String, message: String) -> String {

        validated("activity_\(request)_\(kind)_\(stableHash(message))_\(recipient)")
    }

    /// FNV-1a. Hand-rolled because `hashValue` is seeded per process, so it would produce a different
    /// record name on every launch and defeat the whole point.
    private static func stableHash(_ text: String) -> String {

        var hash: UInt32 = 2166136261

        for byte in text.utf8 { hash = (hash ^ UInt32(byte)) &* 16777619 }

        return String(hash, radix: 16)
    }

    /// `recordName` allows ASCII letters, digits, `-`, `_` and `.` up to 255 characters. CloudKit user
    /// record names start with `_`, which is inside that set. Composed names only exceed the limit if
    /// CloudKit's own identifiers grow, so this is an assertion rather than a thrown error.
    private static func validated(_ name: String) -> String {

        assert(name.count <= 255, "Composed recordName exceeds CloudKit's 255 character limit: \(name)")

        return name
    }
}
