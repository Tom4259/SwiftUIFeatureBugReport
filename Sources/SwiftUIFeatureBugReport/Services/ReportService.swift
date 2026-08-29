//
//  ReportService.swift
//  SwiftUIFeatureBugReport
//

import CloudKit
import Foundation
import Observation

@Observable @MainActor public final class ReportService {

    public private(set) var reportCounts: [CKRecord.ID: Int] = [:]

    /// Category breakdown per request, for the portal's reported queue.
    public private(set) var reportCategories: [CKRecord.ID: [ReportCategory: Int]] = [:]

    /// Requests this user reported. Kept locally as well as on the server so the reporter stops
    /// seeing the content the instant they report it, without waiting for a round trip.
    public private(set) var myReports: Set<CKRecord.ID> = []

    /// Authors this user chose to block. Local-only by design - blocking is a personal preference,
    /// not a moderation decision, and there is nowhere sensible to store it server-side.
    public private(set) var blockedAuthors: Set<String> = []

    private let container: FeedbackContainer

    private var database: CKDatabase { container.database }

    private let blockedAuthorsKey = "com.swiftuifeaturebugreport.blockedAuthors"

    public init(container: FeedbackContainer) {

        self.container = container
        self.blockedAuthors = Set(UserDefaults.standard.stringArray(forKey: blockedAuthorsKey) ?? [])
    }

    func reset() {

        reportCounts = [:]
        reportCategories = [:]
        myReports = []
    }

    public func reportCount(for requestID: CKRecord.ID) -> Int { reportCounts[requestID] ?? 0 }

    public func categories(for requestID: CKRecord.ID) -> [ReportCategory: Int] { reportCategories[requestID] ?? [:] }

    public func hasReported(_ requestID: CKRecord.ID) -> Bool { myReports.contains(requestID) }

    /// Same bulk pattern as votes - one query, `desiredKeys = ["request"]`, grouped client-side.
    public func loadReportCounts() async {

        var counts: [CKRecord.ID: Int] = [:]
        var categories: [CKRecord.ID: [ReportCategory: Int]] = [:]
        var mine: Set<CKRecord.ID> = []

        let query = CKQuery(recordType: RecordType.report, predicate: NSPredicate(value: true))

        var cursor: CKQueryOperation.Cursor?

        repeat {

            do {

                let page: (matchResults: [(CKRecord.ID, Result<CKRecord, any Error>)], queryCursor: CKQueryOperation.Cursor?)

                if let cursor {

                    page = try await database.records(continuingMatchFrom: cursor,
                                                      desiredKeys: [FieldKey.request, FieldKey.category])
                }
                else {

                    page = try await database.records(matching: query,
                                                      desiredKeys: [FieldKey.request, FieldKey.category])
                }

                for (_, result) in page.matchResults {

                    guard let record = try? result.get(),
                          let reference = record[FieldKey.request] as? CKRecord.Reference else { continue }

                    counts[reference.recordID, default: 0] += 1

                    let category = ReportCategory(rawValue: record[FieldKey.category] as? String ?? "") ?? .other

                    categories[reference.recordID, default: [:]][category, default: 0] += 1

                    if container.isCurrentUser(record.creatorUserRecordID) { mine.insert(reference.recordID) }
                }

                cursor = page.queryCursor
            }
            catch {

                break
            }
        }
        while cursor != nil

        reportCounts = counts
        reportCategories = categories
        myReports.formUnion(mine)
    }

    /// Category only. Free text was dropped deliberately: `Report` is world-readable so every client
    /// can compute the threshold, and CloudKit has no per-field permissions - so a "detail" box would
    /// have collected private-feeling prose into a public record. The category is what triage needs.
    public func report(_ requestID: CKRecord.ID, category: ReportCategory) async throws {

        guard let me = container.currentUserRecordID else { throw FeedbackError.notSignedIn }

        // Hide it for the reporter immediately. This is what Apple's UGC requirement actually asks
        // for - the person who objected stops seeing it now, not after a developer gets around to it.
        myReports.insert(requestID)

        let recordID = CKRecord.ID(recordName: RecordID.report(request: requestID.recordName, user: me))
        let record = CKRecord(recordType: RecordType.report, recordID: recordID)

        record[FieldKey.request] = CKRecord.Reference(recordID: requestID, action: .deleteSelf)
        record[FieldKey.category] = category.rawValue

        do {

            _ = try await database.save(record)

            reportCounts[requestID, default: 0] += 1
        }
        catch {

            // Already reported by this user. The local hide above already did the important part.
            guard !CloudKitErrorHandler.isDuplicateRecord(error) else { return }

            throw CloudKitErrorHandler.classify(error)
        }
    }

    // MARK: - Blocking

    public func isBlocked(_ authorID: String) -> Bool { blockedAuthors.contains(authorID) }

    public func block(author authorID: String) {

        blockedAuthors.insert(authorID)
        UserDefaults.standard.set(Array(blockedAuthors), forKey: blockedAuthorsKey)
    }

    public func unblock(author authorID: String) {

        blockedAuthors.remove(authorID)
        UserDefaults.standard.set(Array(blockedAuthors), forKey: blockedAuthorsKey)
    }

    // MARK: - Visibility

    /// The client-side visibility rule (§6.4). Applied everywhere a request could be shown.
    ///
    /// `approved` exists precisely so that a developer clearing a report makes it stick. Without it
    /// the reports stay counted, the threshold is still met, and the request silently re-hides itself
    /// the moment the next client refreshes.
    public func isVisible(_ request: FeedbackRequest, threshold: Int) -> Bool {

        Self.isVisible(moderation: request.moderation,
                       isBlocked: blockedAuthors.contains(request.creatorID),
                       hasReported: hasReported(request.id),
                       reportCount: reportCount(for: request.id),
                       threshold: threshold)
    }

    /// The rule itself, free of any state, so it can be exercised directly. Every branch below is a
    /// decision someone has to be able to check without standing up a CloudKit container.
    nonisolated static func isVisible(moderation: ModerationState,
                                      isBlocked: Bool,
                                      hasReported: Bool,
                                      reportCount: Int,
                                      threshold: Int) -> Bool {

        if isBlocked { return false }

        switch moderation {

        case .hidden: return false
        case .approved: return true
        case .visible: return !hasReported && reportCount < threshold
        }
    }
}
