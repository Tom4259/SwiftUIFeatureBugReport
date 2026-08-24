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

        for chunk in records.chunked(into: maximumOperationSize) {

            try await perform(saving: chunk, deleting: [], in: database)
        }

        for chunk in recordIDs.chunked(into: maximumOperationSize) {

            try await perform(saving: [], deleting: chunk, in: database)
        }
    }

    static func save(_ records: [CKRecord], in database: CKDatabase) async throws {

        try await modify(saving: records, deleting: [], in: database)
    }

    static func delete(_ recordIDs: [CKRecord.ID], in database: CKDatabase) async throws {

        try await modify(saving: [], deleting: recordIDs, in: database)
    }

    private static func perform(saving records: [CKRecord],
                                deleting recordIDs: [CKRecord.ID],
                                in database: CKDatabase) async throws {

        guard !records.isEmpty || !recordIDs.isEmpty else { return }

        do {

            _ = try await database.modifyRecords(saving: records,
                                                 deleting: recordIDs,
                                                 savePolicy: .changedKeys,
                                                 atomically: false)
        }
        catch {

            guard CloudKitErrorHandler.isBatchTooLarge(error),
                  records.count + recordIDs.count > 1 else { throw error }

            // Halve and recurse. Splitting both sides keeps a mixed batch balanced.
            let (saveHead, saveTail) = records.halved()
            let (deleteHead, deleteTail) = recordIDs.halved()

            try await perform(saving: saveHead, deleting: deleteHead, in: database)
            try await perform(saving: saveTail, deleting: deleteTail, in: database)
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
