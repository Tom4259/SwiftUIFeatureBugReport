//
//  RequestService.swift
//  SwiftUIFeatureBugReport
//

import CloudKit
import Foundation
import Observation

@Observable @MainActor public final class RequestService {

    /// Hard cap on a single board load. A public container has no upper bound on how many requests it
    /// might hold, and an unbounded cursor loop on a busy board is a quota incident waiting to happen.
    public static let boardFetchLimit = 500

    /// Records per page.
    ///
    /// **Not** `CKQueryOperation.maximumResults` - that constant is `0`, a sentinel meaning "let the
    /// server choose", so using it as a page size silently asks for nothing at all.
    private static let pageSize = 200

    public private(set) var requests: [FeedbackRequest] = []
    public private(set) var isLoading = false
    public private(set) var hasLoadedOnce = false
    public var error: FeedbackError?

    private let container: FeedbackContainer

    private var database: CKDatabase { container.database }

    public init(container: FeedbackContainer) {

        self.container = container
    }

    func reset() {

        requests = []
        hasLoadedOnce = false
    }

    // MARK: - Reading

    public func loadBoard() async {

        isLoading = true
        error = nil

        defer { isLoading = false }

        // Developers fetch hidden requests too, because the portal is the only place they can be
        // un-hidden. Filtering them out in the query made hiding irreversible: the record vanished
        // from the developer's own list on the next refresh and nothing could bring it back.
        //
        // For everyone else the `!=` predicate stays, so hidden content is never sent to their device.
        // `!=` rather than `IN {visible, approved}` so a moderation state added by a future version
        // still shows up. Records where `moderation` was never written match neither form, which is
        // exactly why the persistence layer always writes it.
        let predicate = container.isDeveloper
            ? NSPredicate(value: true)
            : NSPredicate(format: "%K != %@", FieldKey.moderation, ModerationState.hidden.rawValue)

        let query = CKQuery(recordType: RecordType.request, predicate: predicate)
        query.sortDescriptors = [NSSortDescriptor(key: FieldKey.lastActivityAt, ascending: false)]

        do {

            requests = try await fetchAll(query, desiredKeys: FeedbackRequest.listDesiredKeys, cap: Self.boardFetchLimit)
            hasLoadedOnce = true
        }
        catch {

            self.error = CloudKitErrorHandler.classifyQuery(error)
        }
    }

    /// Cursor loop, capped. The modern async API is the same paginated `CKQueryOperation` underneath -
    /// one page per call, with a cursor to continue from.
    private func fetchAll(_ query: CKQuery, desiredKeys: [String], cap: Int) async throws -> [FeedbackRequest] {

        var collected: [FeedbackRequest] = []
        var cursor: CKQueryOperation.Cursor?

        repeat {

            let pageSize = min(Self.pageSize, cap - collected.count)

            guard pageSize > 0 else { break }

            let page: (matchResults: [(CKRecord.ID, Result<CKRecord, any Error>)], queryCursor: CKQueryOperation.Cursor?)

            if let cursor {

                page = try await database.records(continuingMatchFrom: cursor,
                                                  desiredKeys: desiredKeys,
                                                  resultsLimit: pageSize)
            }
            else {

                page = try await database.records(matching: query,
                                                  desiredKeys: desiredKeys,
                                                  resultsLimit: pageSize)
            }

            for (_, result) in page.matchResults {

                // A record that failed individually is skipped, not thrown - one bad row must not
                // empty the board.
                guard let record = try? result.get(), let request = FeedbackRequest(record: record) else { continue }

                collected.append(request)
            }

            cursor = page.queryCursor
        }
        while cursor != nil && collected.count < cap

        return collected
    }

    /// Fetches the full record including its asset. The **only** place the image is fetched.
    public func loadDetail(_ request: FeedbackRequest) async -> FeedbackRequest {

        do {

            let record = try await database.record(for: request.id)

            guard var detailed = FeedbackRequest(record: record) else { return request }

            if let assets = record[FieldKey.images] as? [CKAsset] {

                detailed.imageURLs = FeedbackImage.copyOut(assets)
            }

            return detailed
        }
        catch {

            if CloudKitErrorHandler.isRecordMissing(error) {

                requests.removeAll { $0.id == request.id }
            }

            return request
        }
    }

    // MARK: - Search

    /// Search-before-submit (§9.1). Includes completed requests deliberately - "fixed in 2.1" is the
    /// most useful thing you can tell someone who is about to file a duplicate.
    ///
    /// CloudKit text search is token-prefix based, not fuzzy: `"dark"` matches "Dark mode",
    /// `"drk mode"` matches nothing. There is no client-side fuzzy fallback and there should not be.
    public func search(_ text: String) async -> [FeedbackRequest] {

        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)

        guard trimmed.count >= 4 else { return [] }

        // `self CONTAINS` is the one documented full-text form, and it searches every SEARCHABLE field
        // of the record type. `title` is the only one, so this *is* a title search - see Schema.ckdb.
        //
        // Do not mark `body` searchable without revisiting this: CloudKit returns matches in no
        // particular order and has no relevance scoring, so widening the match set does not surface
        // better results, it just makes which five you get arbitrary.
        let predicate = NSPredicate(format: "self CONTAINS %@", trimmed)

        let query = CKQuery(recordType: RecordType.request, predicate: predicate)

        do {

            let page = try await database.records(matching: query,
                                                  desiredKeys: FeedbackRequest.searchDesiredKeys,
                                                  resultsLimit: 5)

            return page.matchResults.compactMap { try? $0.1.get() }
                .compactMap { FeedbackRequest(record: $0) }
                .filter { $0.moderation != .hidden }
        }
        catch {

            // A failed search must never block the form. Silently return nothing.
            return []
        }
    }

    // MARK: - Writing

    public func create(title: String,
                       body: String,
                       type: FeedbackType,
                       imageData: [Data],
                       metadata: [String: String]) async throws -> FeedbackRequest {

        guard let creatorID = container.currentUserRecordID else { throw FeedbackError.notSignedIn }

        // Enforced here as well as hidden in the form, so an integrator who flips the flag cannot be
        // caught out by a call site that still passes images.
        let attachments = container.configuration.allowImageAttachments ? imageData : []

        // Encode metadata before writing anything, so an oversized payload fails the submission
        // rather than leaving a request behind with its metadata missing.
        let encodedMetadata = metadata.isEmpty ? nil : try RequestMetadata.encode(metadata)

        // Every field is written here, unconditionally. No branch leaves one absent, because an
        // absent field drops the record out of every `field == value` query against it.
        var seeded = CKRecord(recordType: RecordType.request)

        seeded[FieldKey.title] = title
        seeded[FieldKey.body] = body
        seeded[FieldKey.type] = type.rawValue
        seeded[FieldKey.status] = RequestStatus.open.rawValue
        seeded[FieldKey.moderation] = ModerationState.visible.rawValue
        seeded[FieldKey.imageState] = (attachments.isEmpty ? ImageState.none : ImageState.pending).rawValue
        seeded[FieldKey.labels] = [String]()
        seeded[FieldKey.resolvedInVersion] = ""
        seeded[FieldKey.creatorID] = creatorID
        seeded[FieldKey.lastActivityAt] = Date.now

        let environment = DeviceInfo.current()

        seeded[FieldKey.appVersion] = environment.appVersion
        seeded[FieldKey.buildNumber] = environment.buildNumber
        seeded[FieldKey.osVersion] = environment.osVersion
        seeded[FieldKey.deviceModel] = environment.deviceModel
        seeded[FieldKey.platform] = environment.platform

        if !attachments.isEmpty {

            seeded[FieldKey.images] = try FeedbackImage.prepareForUpload(attachments).map { CKAsset(fileURL: $0) }
        }

        do {

            seeded = try await database.save(seeded)
        }
        catch {

            throw CloudKitErrorHandler.classify(error)
        }

        guard let saved = FeedbackRequest(record: seeded) else { throw FeedbackError.underlying("Could not read back the saved request.") }

        if let encodedMetadata {

            // Best effort: the request itself is already safely stored, so a metadata failure must not
            // lose the user's report. It surfaces in the portal as missing metadata, not as a crash.
            let metadataRecord = CKRecord(recordType: RecordType.requestMetadata,
                                          recordID: CKRecord.ID(recordName: RecordID.metadata(request: saved.id.recordName)))

            metadataRecord[FieldKey.request] = CKRecord.Reference(recordID: saved.id, action: .deleteSelf)
            metadataRecord[FieldKey.payload] = encodedMetadata

            do {

                _ = try await database.save(metadataRecord)
            }
            catch {

                // The request is already stored, so losing its metadata must not lose the report.
                // Surfaced rather than swallowed though: silently dropping developer-supplied
                // diagnostics is worse than a visible warning.
                self.error = CloudKitErrorHandler.classify(error)
            }
        }

        requests.insert(saved, at: 0)

        return saved
    }

    /// Creator edit. Bumps `lastActivityAt` (§3.9).
    public func update(_ request: FeedbackRequest, title: String, body: String) async throws {

        do {

            let record = try await database.record(for: request.id)

            record[FieldKey.title] = title
            record[FieldKey.body] = body
            record[FieldKey.lastActivityAt] = Date.now

            let saved = try await database.save(record)

            replaceLocally(saved)
        }
        catch {

            throw CloudKitErrorHandler.classify(error)
        }
    }

    public func markComplete(_ request: FeedbackRequest) async throws {

        do {

            let record = try await database.record(for: request.id)

            record[FieldKey.status] = RequestStatus.complete.rawValue
            record[FieldKey.lastActivityAt] = Date.now

            let saved = try await database.save(record)

            replaceLocally(saved)
        }
        catch {

            throw CloudKitErrorHandler.classify(error)
        }
    }

    public func delete(_ request: FeedbackRequest) async throws {

        do {

            _ = try await database.deleteRecord(withID: request.id)
        }
        catch {

            // Already gone is the outcome we wanted.
            guard CloudKitErrorHandler.isRecordMissing(error) else { throw CloudKitErrorHandler.classify(error) }
        }

        requests.removeAll { $0.id == request.id }
    }

    func replaceLocally(_ record: CKRecord) {

        guard let updated = FeedbackRequest(record: record) else { return }

        replaceLocally(updated)
    }

    func replaceLocally(_ updated: FeedbackRequest) {

        if let index = requests.firstIndex(where: { $0.id == updated.id }) {

            requests[index] = updated
        }
    }

    func removeLocally(_ id: CKRecord.ID) { requests.removeAll { $0.id == id } }
}
