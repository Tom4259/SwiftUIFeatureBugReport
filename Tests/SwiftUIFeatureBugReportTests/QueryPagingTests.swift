//
//  QueryPagingTests.swift
//  SwiftUIFeatureBugReportTests
//

import CloudKit
import Testing

@testable import SwiftUIFeatureBugReport

private func ckError(_ code: CKError.Code, userInfo: [String: Any] = [:]) -> CKError {

    CKError(_nsError: NSError(domain: CKError.errorDomain, code: code.rawValue, userInfo: userInfo))
}

/// A page of `count` vote records whose names start at `start`, so pages can be told apart.
private func page(_ start: Int, count: Int, cursor: Int?) -> QueryPage<Int> {

    let results: QueryMatchResults = (start ..< start + count).map { index in

        let id = CKRecord.ID(recordName: "vote-\(index)")

        return (id, .success(CKRecord(recordType: RecordType.vote, recordID: id)))
    }

    return (matchResults: results, queryCursor: cursor)
}

private func names(_ results: [QueryMatchResults]) -> [String] {

    results.flatMap { $0.compactMap { try? $0.1.get().recordID.recordName } }
}

/// `CKQueryOperation.Cursor` cannot be constructed, so these drive the shared loop with `Int` cursors.
@Suite("Query paging")
@MainActor
struct QueryPagingTests {

    @Test("A single page without a cursor is fetched once and finishes")
    func singlePage() async {

        var firstCalls = 0
        var continued: [Int] = []
        var seen: [QueryMatchResults] = []

        let outcome = await CloudKitPaging.forEachPage(
            first: { () async throws -> QueryPage<Int> in firstCalls += 1; return page(0, count: 3, cursor: nil) },
            next: { (cursor: Int) async throws -> QueryPage<Int> in continued.append(cursor); return page(0, count: 0, cursor: nil) },
            body: { seen.append($0) })

        #expect(outcome.isFinished)
        #expect(firstCalls == 1)
        #expect(continued.isEmpty)
        #expect(names(seen) == ["vote-0", "vote-1", "vote-2"])
    }

    @Test("Every cursor is followed, in order, until CloudKit stops returning one")
    func followsCursors() async {

        var firstCalls = 0
        var continued: [Int] = []
        var seen: [QueryMatchResults] = []

        let outcome = await CloudKitPaging.forEachPage(
            first: { () async throws -> QueryPage<Int> in firstCalls += 1; return page(0, count: 2, cursor: 1) },
            next: { (cursor: Int) async throws -> QueryPage<Int> in

                continued.append(cursor)

                return page(cursor * 2, count: 2, cursor: cursor < 3 ? cursor + 1 : nil)
            },
            body: { seen.append($0) })

        #expect(outcome.isFinished)
        #expect(firstCalls == 1)
        #expect(continued == [1, 2, 3])
        #expect(seen.count == 4)
        #expect(names(seen) == (0 ..< 8).map { "vote-\($0)" })
    }

    @Test("An empty page that still carries a cursor is followed rather than treated as the end")
    func emptyPageWithCursor() async {

        var seen: [QueryMatchResults] = []

        let outcome = await CloudKitPaging.forEachPage(
            first: { () async throws -> QueryPage<Int> in page(0, count: 0, cursor: 1) },
            next: { (_: Int) async throws -> QueryPage<Int> in page(0, count: 1, cursor: nil) },
            body: { seen.append($0) })

        #expect(outcome.isFinished)
        #expect(names(seen) == ["vote-0"])
    }

    @Test("A continuation that never ends stops at the page cap")
    func stopsAtPageCap() async {

        var pagesFetched = 0

        let outcome = await CloudKitPaging.forEachPage(
            maxPages: 5,
            first: { () async throws -> QueryPage<Int> in pagesFetched += 1; return page(0, count: 1, cursor: 0) },
            next: { (cursor: Int) async throws -> QueryPage<Int> in pagesFetched += 1; return page(0, count: 1, cursor: cursor) },
            body: { _ in })

        #expect(outcome.isPageCap)
        #expect(pagesFetched == 5)
    }

    @Test("The default cap is the documented 200 pages")
    func defaultPageCap() async {

        #expect(CloudKitErrorHandler.maxQueryPages == 200)

        var pagesFetched = 0
        var bodies = 0

        let outcome = await CloudKitPaging.forEachPage(
            first: { () async throws -> QueryPage<Int> in pagesFetched += 1; return page(0, count: 0, cursor: 1) },
            next: { (cursor: Int) async throws -> QueryPage<Int> in pagesFetched += 1; return page(0, count: 0, cursor: cursor + 1) },
            body: { _ in bodies += 1 })

        #expect(outcome.isPageCap)
        #expect(pagesFetched == 200)
        #expect(bodies == 200)
    }

    @Test("Exactly the cap's worth of pages ending without a cursor is a complete load")
    func capBoundaryIsComplete() async {

        let outcome = await CloudKitPaging.forEachPage(
            maxPages: 3,
            first: { () async throws -> QueryPage<Int> in page(0, count: 1, cursor: 1) },
            next: { (cursor: Int) async throws -> QueryPage<Int> in page(cursor, count: 1, cursor: cursor < 2 ? cursor + 1 : nil) },
            body: { _ in })

        #expect(outcome.isFinished)
    }

    @Test("A failing page keeps the pages before it and reports the error")
    func failureKeepsEarlierPages() async {

        var seen: [QueryMatchResults] = []

        let outcome = await CloudKitPaging.forEachPage(
            first: { () async throws -> QueryPage<Int> in page(0, count: 2, cursor: 1) },
            next: { (_: Int) async throws -> QueryPage<Int> in throw ckError(.networkFailure) },
            body: { seen.append($0) })

        #expect(names(seen) == ["vote-0", "vote-1"])

        guard case .failed(let error) = outcome else {

            Issue.record("Expected a failure, got \(outcome)")
            return
        }

        #expect((error as? CKError)?.code == .networkFailure)
    }

    @Test("A failing first page hands nothing to the body")
    func failingFirstPage() async {

        var bodies = 0

        let outcome = await CloudKitPaging.forEachPage(
            first: { () async throws -> QueryPage<Int> in throw ckError(.unknownItem) },
            next: { (_: Int) async throws -> QueryPage<Int> in page(0, count: 1, cursor: nil) },
            body: { _ in bodies += 1 })

        #expect(bodies == 0)

        guard case .failed(let error) = outcome else {

            Issue.record("Expected a failure, got \(outcome)")
            return
        }

        #expect(CloudKitErrorHandler.isRecordMissing(error))
    }
}

/// Entries can fail while their page succeeds; these used to vanish behind `try?`.
@Suite("Per-entry match failures")
struct MatchFailureTests {

    private let recordA = CKRecord.ID(recordName: "a")
    private let recordB = CKRecord.ID(recordName: "b")

    private func success(_ id: CKRecord.ID) -> (CKRecord.ID, Result<CKRecord, any Error>) {

        (id, .success(CKRecord(recordType: RecordType.vote, recordID: id)))
    }

    @Test("A page where everything loaded has no failure")
    func allSucceeded() {

        #expect(CloudKitErrorHandler.firstMatchFailure(in: [success(recordA), success(recordB)]) == nil)
        #expect(CloudKitErrorHandler.firstMatchFailure(in: []) == nil)
    }

    @Test("A record deleted between query and fetch is not a failure")
    func missingIsIgnored() {

        let results: QueryMatchResults = [success(recordA), (recordB, .failure(ckError(.unknownItem)))]

        #expect(CloudKitErrorHandler.firstMatchFailure(in: results) == nil)
    }

    @Test("Any other entry failure is classified and surfaced")
    func otherFailuresSurface() {

        let results: QueryMatchResults = [(recordA, .failure(ckError(.unknownItem))),
                                          success(recordB),
                                          (recordB, .failure(ckError(.networkFailure))),
                                          (recordA, .failure(ckError(.permissionFailure)))]

        // The first non-missing failure wins.
        #expect(CloudKitErrorHandler.firstMatchFailure(in: results) == .networkUnavailable)
    }

    @Test("Hitting the page cap is reported as an incomplete load, not a generic failure")
    func incompleteLoadMessage() {

        guard case .underlying(let message) = CloudKitErrorHandler.incompleteLoad else {

            Issue.record("Expected an underlying message")
            return
        }

        #expect(!message.isEmpty)
    }
}

extension CloudKitPaging.Outcome {

    var isFinished: Bool {

        if case .finished = self { return true }

        return false
    }

    var isPageCap: Bool {

        if case .reachedPageCap = self { return true }

        return false
    }
}
