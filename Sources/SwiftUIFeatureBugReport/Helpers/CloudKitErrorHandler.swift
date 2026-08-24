//
//  CloudKitErrorHandler.swift
//  SwiftUIFeatureBugReport
//

import CloudKit
import Foundation

/// One place every service routes CloudKit errors through, so the awkward cases are handled once.
enum CloudKitErrorHandler {

    /// Maps a raw CloudKit error onto something the UI can show.
    ///
    /// `.partialFailure` is unwrapped first: the top-level error is generic and useless on its own,
    /// and the real reason is always in `CKPartialErrorsByItemIDKey`.
    static func classify(_ error: Error) -> FeedbackError {

        guard let ckError = error as? CKError else {

            return .underlying(error.localizedDescription)
        }

        if ckError.code == .partialFailure,
           let first = partialErrors(in: ckError).values.first {

            return classify(first)
        }

        switch ckError.code {

        case .notAuthenticated, .accountTemporarilyUnavailable:
            return .notSignedIn

        case .networkUnavailable, .networkFailure, .serviceUnavailable:
            return .networkUnavailable

        case .unknownItem:
            return .recordMissing

        case .requestRateLimited, .zoneBusy:
            return .rateLimited(retryAfter: retryDelay(for: ckError) ?? 30)

        // A developer who skipped the security-role setup step otherwise gets a raw permission error
        // that reads like a bug in this package. Name the actual cause instead.
        case .permissionFailure:
            return .developerRoleNotConfigured

        default:
            return .underlying(ckError.localizedDescription)
        }
    }

    /// Same as `classify`, for errors coming out of a **query** rather than a fetch by record ID.
    ///
    /// CloudKit reuses `.unknownItem` for two very different things: "that record is gone" when you
    /// fetch by ID, and "that record *type* does not exist" when you query. Only the call site knows
    /// which, and conflating them tells a developer whose schema is missing from Production that an
    /// item was deleted - which sends them looking in entirely the wrong place.
    static func classifyQuery(_ error: Error) -> FeedbackError {

        let classified = classify(error)

        return classified == .recordMissing ? .schemaNotDeployed : classified
    }

    /// How long the server asked us to wait. Callers must disable the retry affordance for this long:
    /// a user able to spam-tap retry into an active rate limit only extends it.
    static func retryDelay(for error: Error) -> TimeInterval? {

        guard let ckError = error as? CKError else { return nil }

        if let seconds = ckError.userInfo[CKErrorRetryAfterKey] as? Double { return seconds }

        // A partial failure carries the retry hint on the individual item error, not the wrapper.
        return partialErrors(in: ckError).values
            .compactMap { ($0 as? CKError)?.userInfo[CKErrorRetryAfterKey] as? Double }
            .max()
    }

    static func partialErrors(in error: Error) -> [CKRecord.ID: Error] {

        guard let ckError = error as? CKError,
              let byItem = ckError.userInfo[CKPartialErrorsByItemIDKey] as? [CKRecord.ID: Error] else {

            return [:]
        }

        return byItem
    }

    /// A duplicate save is the **success** path for votes and reports (§4). The deterministic record
    /// name means a second save of the same vote fails server-side, and that failure is precisely how
    /// one-vote-per-user is enforced. After a reinstall or on a second device this is the normal
    /// outcome, not an exceptional one.
    static func isDuplicateRecord(_ error: Error) -> Bool {

        guard let ckError = error as? CKError else { return false }

        if ckError.code == .serverRecordChanged { return true }

        if ckError.code == .partialFailure {

            return partialErrors(in: ckError).values.contains { isDuplicateRecord($0) }
        }

        return false
    }

    /// Whether *every* item in a batch failed as a duplicate.
    ///
    /// Distinct from `isDuplicateRecord`, which is true if any single item collided. Re-sending an
    /// announcement everyone already has should read as success; a batch where only some collided is
    /// a genuine partial failure and still needs reporting.
    static func isEntirelyDuplicates(_ error: Error) -> Bool {

        guard let ckError = error as? CKError else { return false }

        if ckError.code == .serverRecordChanged { return true }

        guard ckError.code == .partialFailure else { return false }

        let failures = partialErrors(in: ckError)

        return !failures.isEmpty && failures.values.allSatisfy { ($0 as? CKError)?.code == .serverRecordChanged }
    }

    /// The record is gone - a developer deleted it. Drop it from the local list; never a toast.
    static func isRecordMissing(_ error: Error) -> Bool {

        guard let ckError = error as? CKError else { return false }

        if ckError.code == .unknownItem { return true }

        if ckError.code == .partialFailure {

            return partialErrors(in: ckError).values.allSatisfy { isRecordMissing($0) }
        }

        return false
    }

    static func isBatchTooLarge(_ error: Error) -> Bool {

        guard let ckError = error as? CKError else { return false }

        return ckError.code == .limitExceeded
    }
}
