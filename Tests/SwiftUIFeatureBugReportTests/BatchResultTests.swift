//
//  BatchResultTests.swift
//  SwiftUIFeatureBugReportTests
//

import CloudKit
import Testing

@testable import SwiftUIFeatureBugReport

private let recordA = CKRecord.ID(recordName: "a")
private let recordB = CKRecord.ID(recordName: "b")

private func saved(_ id: CKRecord.ID) -> Result<CKRecord, any Error> {

    .success(CKRecord(recordType: RecordType.activity, recordID: id))
}

private func partialFailure(_ errors: [CKRecord.ID: Error]) -> CKError {

    CKError(.partialFailure, userInfo: [CKPartialErrorsByItemIDKey: errors])
}

/// `modifyRecords(atomically: false)` succeeds overall even when records fail; the failures are only in
/// the per-record results, so these decide whether a batch write really completed.
@Suite("Batch per-record results")
struct BatchResultTests {

    @Test("All records written is success")
    func allSucceeded() throws {

        try CloudKitBatch.throwFirstUnexpectedFailure(saveResults: [recordA: saved(recordA)],
                                                      deleteResults: [recordB: .success(())])

        try CloudKitBatch.throwFirstUnexpectedFailure(saveResults: [:], deleteResults: [:])
    }

    @Test("Deleting a record that is already gone, or saving one that already exists, is success")
    func expectedOutcomesAreSuccess() throws {

        try CloudKitBatch.throwFirstUnexpectedFailure(saveResults: [recordA: .failure(CKError(.serverRecordChanged))],
                                                      deleteResults: [recordB: .failure(CKError(.unknownItem))])
    }

    @Test("A real per-record failure throws even when the rest succeeded")
    func realFailureThrows() {

        #expect(throws: CKError.self) {

            try CloudKitBatch.throwFirstUnexpectedFailure(saveResults: [recordA: saved(recordA),
                                                                        recordB: .failure(CKError(.permissionFailure))],
                                                          deleteResults: [:])
        }

        #expect(throws: CKError.self) {

            try CloudKitBatch.throwFirstUnexpectedFailure(saveResults: [:],
                                                          deleteResults: [recordA: .success(()),
                                                                          recordB: .failure(CKError(.networkFailure))])
        }
    }

    @Test("Missing on save is not excused, and a collision on delete is not either")
    func excusesDoNotCross() {

        #expect(CloudKitBatch.firstUnexpectedFailure(saveErrors: [CKError(.unknownItem)], deleteErrors: []) != nil)
        #expect(CloudKitBatch.firstUnexpectedFailure(saveErrors: [], deleteErrors: [CKError(.serverRecordChanged)]) != nil)
    }

    @Test("A delete failure is reported ahead of a save failure")
    func deleteFailureFirst() throws {

        let failure = try #require(CloudKitBatch.firstUnexpectedFailure(saveErrors: [CKError(.networkFailure)],
                                                                        deleteErrors: [CKError(.permissionFailure)]))

        #expect((failure as? CKError)?.code == .permissionFailure)
    }

    @Test("Per-item errors wrapped in a partial failure are classified by their contents")
    func wrappedErrors() {

        #expect(CloudKitBatch.firstUnexpectedFailure(saveErrors: [partialFailure([recordA: CKError(.serverRecordChanged)])],
                                                     deleteErrors: [partialFailure([recordB: CKError(.unknownItem)])]) == nil)

        #expect(CloudKitBatch.firstUnexpectedFailure(saveErrors: [],
                                                     deleteErrors: [partialFailure([recordA: CKError(.unknownItem),
                                                                                    recordB: CKError(.networkFailure)])]) != nil)

        #expect(CloudKitBatch.firstUnexpectedFailure(saveErrors: [partialFailure([recordA: CKError(.serverRecordChanged),
                                                                                  recordB: CKError(.networkFailure)])],
                                                     deleteErrors: []) != nil)
    }

    @Test("An unexpected per-record failure stops the remaining chunks")
    func failureStopsLaterChunks() async {

        let records = (0 ..< 500).map { CKRecord(recordType: RecordType.activity, recordID: CKRecord.ID(recordName: "r\($0)")) }
        var calls = 0

        await #expect(throws: CKError.self) {

            try await CloudKitBatch.modify(saving: records, deleting: []) { saving, _ in

                calls += 1

                // The first record of each batch hits a permission failure; the rest succeed.
                var results: [CKRecord.ID: Result<CKRecord, any Error>] = [:]

                for (index, record) in saving.enumerated() {

                    results[record.recordID] = index == 0 ? .failure(CKError(.permissionFailure)) : .success(record)
                }

                try CloudKitBatch.throwFirstUnexpectedFailure(saveResults: results, deleteResults: [:])
            }
        }

        #expect(calls == 1)
    }

    @Test("Collisions across every chunk still complete the whole write")
    func collisionsComplete() async throws {

        let records = (0 ..< 500).map { CKRecord(recordType: RecordType.activity, recordID: CKRecord.ID(recordName: "r\($0)")) }
        var calls = 0

        try await CloudKitBatch.modify(saving: records, deleting: []) { saving, _ in

            calls += 1

            let results = Dictionary(uniqueKeysWithValues: saving.map { record -> (CKRecord.ID, Result<CKRecord, any Error>) in

                (record.recordID, .failure(CKError(.serverRecordChanged)))
            })

            try CloudKitBatch.throwFirstUnexpectedFailure(saveResults: results, deleteResults: [:])
        }

        #expect(calls == 2)
    }
}
