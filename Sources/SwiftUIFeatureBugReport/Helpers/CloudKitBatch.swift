//
//  CloudKitBatch.swift
//  SwiftUIFeatureBugReport
//

import CloudKit
import Foundation

/// Every multi-record write goes through here (§7).
///
/// CloudKit rejects an oversized batch with `.limitExceeded` and tells you nothing about the right
/// size, so the only workable response is to halve and retry. Without this, notifying the voters of a
/// popular request, bulk-hiding a prolific author, or deleting a heavy user's data simply fails.
enum CloudKitBatch {

    /// CloudKit's documented per-operation ceiling. The splitter handles the cases where the real
    /// limit is lower because the records themselves are large.
    static let maximumOperationSize = 400

    static func modify(saving records: [CKRecord],
                       deleting recordIDs: [CKRecord.ID],
                       in database: CKDatabase) async throws {

        try await modify(saving: records, deleting: recordIDs) { saving, deleting in

            let results = try await database.modifyRecords(saving: saving,
                                                           deleting: deleting,
                                                           savePolicy: .changedKeys,
                                                           atomically: false)

            try throwFirstUnexpectedFailure(saveResults: results.saveResults, deleteResults: results.deleteResults)
        }
    }

    /// One `modifyRecords` call. Injected so the chunking and splitting can be tested without CloudKit.
    typealias Write = (_ saving: [CKRecord], _ deleting: [CKRecord.ID]) async throws -> Void

    /// Chunks into `maximumOperationSize` batches - saves first, then deletes - and halves any batch
    /// `write` rejects as too large.
    static func modify(saving records: [CKRecord],
                       deleting recordIDs: [CKRecord.ID],
                       using write: Write) async throws {

        for chunk in records.chunked(into: maximumOperationSize) {

            try await perform(saving: chunk, deleting: [], using: write)
        }

        for chunk in recordIDs.chunked(into: maximumOperationSize) {

            try await perform(saving: [], deleting: chunk, using: write)
        }
    }

    static func save(_ records: [CKRecord], in database: CKDatabase) async throws {

        try await modify(saving: records, deleting: [], in: database)
    }

    static func delete(_ recordIDs: [CKRecord.ID], in database: CKDatabase) async throws {

        try await modify(saving: [], deleting: recordIDs, in: database)
    }

    /// The first per-record failure that is not an expected outcome.
    ///
    /// - A delete of a record that is already gone succeeded in every way that matters.
    /// - A save that collides with an existing record is how deterministic record names deduplicate
    ///   (a repeated announcement, a second vote), so it is not a failure either.
    ///
    /// Anything else - a permission failure, a network drop, a rate limit - is returned so the caller
    /// stops instead of reporting completion.
    static func firstUnexpectedFailure(saveErrors: [any Error], deleteErrors: [any Error]) -> (any Error)? {

        if let failure = deleteErrors.first(where: { !CloudKitErrorHandler.isRecordMissing($0) }) { return failure }

        return saveErrors.first { !CloudKitErrorHandler.isEntirelyDuplicates($0) }
    }

    /// Throws the first unexpected per-record failure in a `modifyRecords(atomically: false)` result.
    ///
    /// With `atomically: false` the call succeeds overall even when individual records fail, and the
    /// failures are only in these results. Ignoring them made a failed delete look done.
    static func throwFirstUnexpectedFailure(saveResults: [CKRecord.ID: Result<CKRecord, any Error>],
                                            deleteResults: [CKRecord.ID: Result<Void, any Error>]) throws {

        let saveErrors = saveResults.values.compactMap { result -> (any Error)? in

            if case .failure(let error) = result { return error }

            return nil
        }

        let deleteErrors = deleteResults.values.compactMap { result -> (any Error)? in

            if case .failure(let error) = result { return error }

            return nil
        }

        if let failure = firstUnexpectedFailure(saveErrors: saveErrors, deleteErrors: deleteErrors) { throw failure }
    }

    private static func perform(saving records: [CKRecord],
                                deleting recordIDs: [CKRecord.ID],
                                using write: Write) async throws {

        guard !records.isEmpty || !recordIDs.isEmpty else { return }

        do {

            try await write(records, recordIDs)
        }
        catch {

            guard CloudKitErrorHandler.isBatchTooLarge(error),
                  records.count + recordIDs.count > 1 else { throw error }

            // Halve and recurse. Splitting both sides keeps a mixed batch balanced.
            let (saveHead, saveTail) = records.halved()
            let (deleteHead, deleteTail) = recordIDs.halved()

            try await perform(saving: saveHead, deleting: deleteHead, using: write)
            try await perform(saving: saveTail, deleting: deleteTail, using: write)
        }
    }
}


extension Array {

    func chunked(into size: Int) -> [[Element]] {

        guard size > 0, count > size else { return isEmpty ? [] : [self] }

        return stride(from: 0, to: count, by: size).map { Array(self[$0 ..< Swift.min($0 + size, count)]) }
    }

    func halved() -> ([Element], [Element]) {

        guard count > 1 else { return (self, []) }

        let middle = count / 2

        return (Array(self[..<middle]), Array(self[middle...]))
    }
}
