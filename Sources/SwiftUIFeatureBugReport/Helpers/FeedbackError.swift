//
//  FeedbackError.swift
//  SwiftUIFeatureBugReport
//

import Foundation

public enum FeedbackError: LocalizedError, Sendable {

    /// No iCloud account. Read-only, not a failure - see `FeedbackContainer.identityState`.
    case notSignedIn

    /// Identity has not resolved yet. Views should wait rather than render "not mine, not voted".
    case identityUnavailable

    case metadataTooLarge(bytes: Int, limit: Int)

    /// The misconfiguration case. Almost always a skipped setup step rather than a package bug.
    case developerRoleNotConfigured

    case rateLimited(retryAfter: TimeInterval)

    case networkUnavailable

    /// The record is gone - usually because a developer deleted it. Handled silently at call sites.
    case recordMissing

    /// The record *type* does not exist in this environment. Almost always a schema that was imported
    /// into Development but never deployed to Production.
    case schemaNotDeployed

    case imageEncodingFailed

    case underlying(String)

    public var errorDescription: String? {

        switch self {

        case .notSignedIn:
            return String(localized: "Sign in to iCloud to post, vote or comment. You can still read the board.")

        case .identityUnavailable:
            return String(localized: "Still checking your iCloud account. Try again in a moment.")

        case .metadataTooLarge(let bytes, let limit):
            return String(localized: "The attached metadata is \(bytes) bytes, over the \(limit) byte limit.")

        case .developerRoleNotConfigured:
            return String(localized: "CloudKit developer role not configured. See README setup step 4.")

        case .rateLimited(let retryAfter):
            return String(localized: "Too many requests. Try again in \(Int(retryAfter.rounded(.up))) seconds.")

        case .networkUnavailable:
            return String(localized: "No network connection.")

        case .recordMissing:
            return String(localized: "That item no longer exists.")

        case .schemaNotDeployed:
            return String(localized: "This app's feedback schema isn't set up in this CloudKit environment. If this is a production build, deploy the schema to Production in the CloudKit Dashboard.")

        case .imageEncodingFailed:
            return String(localized: "That image could not be prepared for upload.")

        case .underlying(let message):
            return message
        }
    }
}
