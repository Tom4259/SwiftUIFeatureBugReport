//
//  CloudKitPaging.swift
//  SwiftUIFeatureBugReport
//

import CloudKit
import Foundation

/// The match results of one query page.
typealias QueryMatchResults = [(CKRecord.ID, Result<CKRecord, any Error>)]

/// One page of a CloudKit query. Generic over the cursor so the paging loop can be exercised in
/// tests: `CKQueryOperation.Cursor` has no public initialiser.
typealias QueryPage<Cursor> = (matchResults: QueryMatchResults, queryCursor: Cursor?)

/// The cursor-following loop shared by every paged query that needs the page cap.
///
/// Follows `queryCursor` until CloudKit stops returning one, but never fetches more than `maxPages`
/// pages: cursors are opaque, so a continuation that never advances cannot be detected any other way.
/// What to report when a load stops early is left to the caller, because callers differ.
enum CloudKitPaging {

    enum Outcome {

        /// The last page came back without a cursor.
        case finished

        /// `maxPages` pages were fetched and CloudKit still offered another.
        case reachedPageCap

        /// Fetching a page threw. The pages before it were already handed to `body`.
        case failed(any Error)
    }

    @MainActor
    static func forEachPage<Cursor>(maxPages: Int = CloudKitErrorHandler.maxQueryPages,
                                    first: () async throws -> QueryPage<Cursor>,
                                    next: (Cursor) async throws -> QueryPage<Cursor>,
                                    body: (QueryMatchResults) -> Void) async -> Outcome {

        var cursor: Cursor?
        var pages = 0

        repeat {

            guard pages < maxPages else { return .reachedPageCap }

            pages += 1

            do {

                let page: QueryPage<Cursor>

                if let cursor {

                    page = try await next(cursor)
                }
                else {

                    page = try await first()
                }

                body(page.matchResults)

                cursor = page.queryCursor
            }
            catch {

                return .failed(error)
            }
        }
        while cursor != nil

        return .finished
    }
}
