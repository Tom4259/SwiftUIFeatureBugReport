//
//  CloudKitBatchTests.swift
//  SwiftUIFeatureBugReportTests
//

import CloudKit
import Testing

@testable import SwiftUIFeatureBugReport

private func ckError(_ code: CKError.Code) -> CKError {

    CKError(_nsError: NSError(domain: CKError.errorDomain, code: code.rawValue, userInfo: nil))
}

private func records(_ count: Int) -> [CKRecord] {

    (0 ..< count).map { CKRecord(recordType: RecordType.vote, recordID: CKRecord.ID(recordName: "r\($0)")) }
}

private func recordIDs(_ count: Int) -> [CKRecord.ID] {

    (0 ..< count).map { CKRecord.ID(recordName: "d\($0)") }
}

/// What one `modifyRecords` call was asked to do.
private struct Call: Equatable {

    let saves: Int
    let deletes: Int
}

@Suite("Batch chunking")
struct ArrayChunkingTests {

    @Test("Chunks never exceed the size and keep every element in order")
    func chunksInOrder() {

        let chunks = Array(0 ..< 1_000).chunked(into: 400)

        #expect(chunks.map(\.count) == [400, 400, 200])
        #expect(chunks.flatMap { $0 } == Array(0 ..< 1_000))
    }

    @Test("At or under the size is a single chunk; empty is no chunks")
    func boundaries() {

        #expect(Array(0 ..< 400).chunked(into: 400).map(\.count) == [400])
        #expect(Array(0 ..< 401).chunked(into: 400).map(\.count) == [400, 1])
        #expect(Array(0 ..< 1).chunked(into: 400).map(\.count) == [1])
        #expect([Int]().chunked(into: 400).isEmpty)
    }

    @Test("A non-positive size does not trap; it falls back to one chunk")
    func nonPositiveSize() {

        #expect([1, 2, 3].chunked(into: 0) == [[1, 2, 3]])
        #expect([Int]().chunked(into: 0).isEmpty)
    }

    @Test("Halving splits at the middle and leaves a single element alone")
    func halving() {

        let (evenHead, evenTail) = [1, 2, 3, 4].halved()
        let (oddHead, oddTail) = [1, 2, 3].halved()
        let (singleHead, singleTail) = [1].halved()
        let (emptyHead, emptyTail) = [Int]().halved()

        #expect(evenHead == [1, 2] && evenTail == [3, 4])
        #expect(oddHead == [1] && oddTail == [2, 3])
        #expect(singleHead == [1] && singleTail.isEmpty)
        #expect(emptyHead.isEmpty && emptyTail.isEmpty)
    }

    @Test("The per-operation ceiling is CloudKit's documented 400")
    func ceiling() {

        #expect(CloudKitBatch.maximumOperationSize == 400)
    }
}

@Suite("Batch writes")
struct CloudKitBatchWriteTests {

    @Test("Saves and deletes go out in 400-record operations, saves first")
    func chunksIntoOperations() async throws {

        var calls: [Call] = []

        try await CloudKitBatch.modify(saving: records(900), deleting: recordIDs(401)) { saving, deleting in

            calls.append(Call(saves: saving.count, deletes: deleting.count))
        }

        #expect(calls == [Call(saves: 400, deletes: 0),
                          Call(saves: 400, deletes: 0),
                          Call(saves: 100, deletes: 0),
                          Call(saves: 0, deletes: 400),
                          Call(saves: 0, deletes: 1)])
    }

    @Test("Nothing to write makes no call at all")
    func emptyIsNoCall() async throws {

        var calls = 0

        try await CloudKitBatch.modify(saving: [], deleting: []) { _, _ in calls += 1 }

        #expect(calls == 0)
    }

    @Test("Every record is written exactly once")
    func everyRecordOnce() async throws {

        var saved: [String] = []
        var deleted: [String] = []

        try await CloudKitBatch.modify(saving: records(850), deleting: recordIDs(10)) { saving, deleting in

            saved += saving.map(\.recordID.recordName)
            deleted += deleting.map(\.recordName)
        }

        #expect(saved == records(850).map(\.recordID.recordName))
        #expect(deleted == recordIDs(10).map(\.recordName))
    }

    @Test("A batch rejected as too large is halved until it fits")
    func halvesOnLimitExceeded() async throws {

        var accepted: [Int] = []
        var rejected = 0

        // Pretend the records are heavy enough that the server only takes 100 at a time.
        try await CloudKitBatch.modify(saving: records(400), deleting: []) { saving, _ in

            guard saving.count <= 100 else { rejected += 1; throw ckError(.limitExceeded) }

            accepted.append(saving.count)
        }

        #expect(accepted == [100, 100, 100, 100])
        #expect(rejected == 3)            // 400, then each 200 half
    }

    @Test("A single record that is still too large surfaces the error instead of looping")
    func singleRecordTooLarge() async {

        var calls = 0

        await #expect(throws: CKError.self) {

            try await CloudKitBatch.modify(saving: records(1), deleting: []) { _, _ in

                calls += 1
                throw ckError(.limitExceeded)
            }
        }

        #expect(calls == 1)
    }

    @Test("Any other failure is thrown at once, without splitting or later chunks")
    func otherErrorsPropagate() async {

        var calls = 0

        await #expect(throws: CKError.self) {

            try await CloudKitBatch.modify(saving: records(800), deleting: recordIDs(5)) { _, _ in

                calls += 1
                throw ckError(.networkFailure)
            }
        }

        #expect(calls == 1)
    }
}
