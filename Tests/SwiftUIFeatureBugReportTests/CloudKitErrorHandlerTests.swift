//
//  CloudKitErrorHandlerTests.swift
//  SwiftUIFeatureBugReportTests
//

import CloudKit
import Testing

@testable import SwiftUIFeatureBugReport

private func ckError(_ code: CKError.Code, userInfo: [String: Any] = [:]) -> CKError {

    CKError(_nsError: NSError(domain: CKError.errorDomain, code: code.rawValue, userInfo: userInfo))
}

/// Wraps `errors` the way CloudKit does for a batch operation.
private func partialFailure(_ errors: [CKRecord.ID: Error]) -> CKError {

    ckError(.partialFailure, userInfo: [CKPartialErrorsByItemIDKey: errors])
}

private let recordA = CKRecord.ID(recordName: "a")
private let recordB = CKRecord.ID(recordName: "b")

@Suite("CloudKit error classification")
struct CloudKitErrorHandlerTests {

    @Test("Permission failure names the setup step rather than reading as a package bug")
    func permissionFailureIsDiagnosed() {

        #expect(CloudKitErrorHandler.classify(ckError(.permissionFailure)) == .developerRoleNotConfigured)
    }

    @Test("Account and network codes map to their own cases")
    func commonCodes() {

        #expect(CloudKitErrorHandler.classify(ckError(.notAuthenticated)) == .notSignedIn)
        #expect(CloudKitErrorHandler.classify(ckError(.accountTemporarilyUnavailable)) == .notSignedIn)
        #expect(CloudKitErrorHandler.classify(ckError(.networkUnavailable)) == .networkUnavailable)
        #expect(CloudKitErrorHandler.classify(ckError(.networkFailure)) == .networkUnavailable)
        #expect(CloudKitErrorHandler.classify(ckError(.serviceUnavailable)) == .networkUnavailable)
        #expect(CloudKitErrorHandler.classify(ckError(.unknownItem)) == .recordMissing)
    }

    /// A partial failure's top-level error says nothing useful; the reason is always on the item.
    @Test("Partial failures are unwrapped to the underlying reason")
    func partialFailureIsUnwrapped() {

        let wrapped = partialFailure([recordA: ckError(.permissionFailure)])

        #expect(CloudKitErrorHandler.classify(wrapped) == .developerRoleNotConfigured)
    }

    /// CloudKit reuses `.unknownItem` for "that record is gone" on a fetch and "that record *type*
    /// does not exist" on a query. Conflating them sends a developer whose schema is missing from
    /// Production looking for a deleted record instead.
    @Test("A query's unknownItem means the schema is missing, not the record")
    func queryUnknownItemIsSchemaNotDeployed() {

        #expect(CloudKitErrorHandler.classifyQuery(ckError(.unknownItem)) == .schemaNotDeployed)
        #expect(CloudKitErrorHandler.classifyQuery(ckError(.networkFailure)) == .networkUnavailable)
    }

    @Test("The retry delay is read from the item error as well as the wrapper")
    func retryDelay() {

        #expect(CloudKitErrorHandler.retryDelay(for: ckError(.requestRateLimited,
                                                             userInfo: [CKErrorRetryAfterKey: 12.0])) == 12.0)

        let wrapped = partialFailure([recordA: ckError(.requestRateLimited, userInfo: [CKErrorRetryAfterKey: 7.0])])

        #expect(CloudKitErrorHandler.retryDelay(for: wrapped) == 7.0)
    }

    @Test("Rate limiting carries the server's delay, defaulting when it gives none")
    func rateLimitedCarriesDelay() {

        #expect(CloudKitErrorHandler.classify(ckError(.requestRateLimited,
                                                     userInfo: [CKErrorRetryAfterKey: 12.0])) == .rateLimited(retryAfter: 12))

        #expect(CloudKitErrorHandler.classify(ckError(.requestRateLimited)) == .rateLimited(retryAfter: 30))
    }

    /// A duplicate save is the success path for votes and reports - it is how one-per-user is
    /// enforced - so it must never be reported as a failure.
    @Test("Duplicate detection sees through a partial failure")
    func duplicateDetection() {

        #expect(CloudKitErrorHandler.isDuplicateRecord(ckError(.serverRecordChanged)))
        #expect(CloudKitErrorHandler.isDuplicateRecord(partialFailure([recordA: ckError(.serverRecordChanged)])))
        #expect(CloudKitErrorHandler.isDuplicateRecord(ckError(.networkFailure)) == false)
    }

    /// Distinct from `isDuplicateRecord`: re-sending an announcement everyone already has should read
    /// as success, but a batch where only some items collided is a genuine partial failure.
    @Test("A wholly duplicate batch is success; a mixed one is not")
    func entirelyDuplicates() {

        #expect(CloudKitErrorHandler.isEntirelyDuplicates(partialFailure([recordA: ckError(.serverRecordChanged),
                                                                         recordB: ckError(.serverRecordChanged)])))

        #expect(CloudKitErrorHandler.isEntirelyDuplicates(partialFailure([recordA: ckError(.serverRecordChanged),
                                                                         recordB: ckError(.networkFailure)])) == false)

        #expect(CloudKitErrorHandler.isEntirelyDuplicates(partialFailure([:])) == false)
    }

    @Test("A missing record is only missing when every item in the batch is")
    func recordMissing() {

        #expect(CloudKitErrorHandler.isRecordMissing(ckError(.unknownItem)))
        #expect(CloudKitErrorHandler.isRecordMissing(partialFailure([recordA: ckError(.unknownItem),
                                                                    recordB: ckError(.unknownItem)])))

        #expect(CloudKitErrorHandler.isRecordMissing(partialFailure([recordA: ckError(.unknownItem),
                                                                    recordB: ckError(.networkFailure)])) == false)
    }

    @Test("A non-CloudKit error keeps its own message")
    func nonCloudKitError() {

        let error = NSError(domain: "test", code: 1, userInfo: [NSLocalizedDescriptionKey: "Something else"])

        #expect(CloudKitErrorHandler.classify(error) == .underlying("Something else"))
    }
}
