//
//  RecordMappingTests.swift
//  SwiftUIFeatureBugReportTests
//

import CloudKit
import Testing

@testable import SwiftUIFeatureBugReport

/// Fields are mapped by hand rather than through `Codable`, so nothing catches a typo in a key except
/// a test. The invariant that matters most is that **every** field is written on create: CloudKit
/// does not match records where a field was never written, so an unwritten field silently drops the
/// record out of any `field == value` query - the board's own query included.
@Suite("Request record mapping")
struct RequestMappingTests {

    private func makeRecord() -> CKRecord {

        let record = CKRecord(recordType: RecordType.request,
                              recordID: CKRecord.ID(recordName: "req1"))

        record[FieldKey.title] = "Chart colours hard to read"
        record[FieldKey.body] = "Two very similar blues."
        record[FieldKey.type] = FeedbackType.bug.rawValue
        record[FieldKey.status] = RequestStatus.inProgress.rawValue
        record[FieldKey.moderation] = ModerationState.hidden.rawValue
        record[FieldKey.imageState] = ImageState.pending.rawValue
        record[FieldKey.labels] = ["ui", "charts"]
        record[FieldKey.resolvedInVersion] = "2.1"
        record[FieldKey.creatorID] = "_user1"
        record[FieldKey.appVersion] = "1.1.0"
        record[FieldKey.buildNumber] = "15"
        record[FieldKey.osVersion] = "26.0"
        record[FieldKey.deviceModel] = "arm64"
        record[FieldKey.platform] = "macOS"
        record[FieldKey.lastActivityAt] = Date(timeIntervalSince1970: 1_000)
        record[FieldKey.workaroundCommentID] = "devComment1"

        return record
    }

    @Test("Every field round-trips out of a record")
    func readsEveryField() throws {

        let request = try #require(FeedbackRequest(record: makeRecord()))

        #expect(request.title == "Chart colours hard to read")
        #expect(request.body == "Two very similar blues.")
        #expect(request.type == .bug)
        #expect(request.status == .inProgress)
        #expect(request.moderation == .hidden)
        #expect(request.imageState == .pending)
        #expect(request.labels == ["ui", "charts"])
        #expect(request.resolvedInVersion == "2.1")
        #expect(request.creatorID == "_user1")
        #expect(request.environment.appVersion == "1.1.0")
        #expect(request.environment.buildNumber == "15")
        #expect(request.environment.osVersion == "26.0")
        #expect(request.environment.deviceModel == "arm64")
        #expect(request.environment.platform == "macOS")
        #expect(request.lastActivityAt == Date(timeIntervalSince1970: 1_000))
        #expect(request.workaroundCommentID == "devComment1")
    }

    /// Every request created before workarounds existed has no `workaroundCommentID` at all - and new
    /// ones are created without it too, deliberately. Absent has to read as "no workaround".
    @Test("A record without a workaround field reads as having none")
    func missingWorkaroundField() throws {

        let record = makeRecord()
        record[FieldKey.workaroundCommentID] = nil

        let request = try #require(FeedbackRequest(record: record))

        #expect(request.workaroundCommentID.isEmpty)
        #expect(request.showsWorkaround == false)
    }

    @Test("Acknowledged is read as itself, not as the open fallback")
    func acknowledgedParses() throws {

        let record = makeRecord()
        record[FieldKey.status] = "acknowledged"

        let request = try #require(FeedbackRequest(record: record))

        #expect(request.status == .acknowledged)
        #expect(RequestStatus.acknowledged.rawValue == "acknowledged")
    }

    @Test("A workaround is badged until the request is complete")
    func workaroundBadgeStopsAtComplete() throws {

        let record = makeRecord()

        for status in RequestStatus.allCases {

            record[FieldKey.status] = status.rawValue

            let request = try #require(FeedbackRequest(record: record))

            #expect(request.showsWorkaround == (status != .complete), "\(status.rawValue)")
        }
    }

    @Test("A record of the wrong type is rejected rather than half-parsed")
    func wrongRecordType() {

        let record = CKRecord(recordType: RecordType.vote, recordID: CKRecord.ID(recordName: "v1"))

        #expect(FeedbackRequest(record: record) == nil)
    }

    /// The enum defaults matter: a record written by a *newer* version carrying a state this build
    /// does not know about must land somewhere safe rather than failing to parse.
    @Test("Unknown enum values fall back instead of dropping the record")
    func unknownEnumValues() throws {

        let record = makeRecord()
        record[FieldKey.type] = "somethingNew"
        record[FieldKey.status] = "somethingNew"
        record[FieldKey.moderation] = "somethingNew"
        record[FieldKey.imageState] = "somethingNew"

        let request = try #require(FeedbackRequest(record: record))

        #expect(request.type == .bug)
        #expect(request.status == .open)
        #expect(request.moderation == .visible)
        #expect(request.imageState == .none)
    }

    /// Writing back must set every field, including the ones left empty, or the record falls out of
    /// equality queries. `images` is the one deliberate exception - assets are managed separately so
    /// that list queries never fetch them.
    @Test("Applying to a record writes every field, empty ones included")
    func writesEveryField() throws {

        let request = try #require(FeedbackRequest(record: makeRecord()))
        let target = CKRecord(recordType: RecordType.request, recordID: CKRecord.ID(recordName: "req2"))

        request.apply(to: target)

        let required = [
            FieldKey.title, FieldKey.body, FieldKey.type, FieldKey.status, FieldKey.moderation,
            FieldKey.imageState, FieldKey.labels, FieldKey.resolvedInVersion, FieldKey.creatorID,
            FieldKey.appVersion, FieldKey.buildNumber, FieldKey.osVersion, FieldKey.deviceModel,
            FieldKey.platform, FieldKey.lastActivityAt, FieldKey.workaroundCommentID
        ]

        for key in required {

            #expect(target[key] != nil, "\(key) was not written, so the record drops out of queries on it")
        }

        #expect(target[FieldKey.images] == nil, "assets are managed separately")
    }
}


@Suite("Metadata payload")
struct RequestMetadataTests {

    @Test("Values round-trip through the JSON payload")
    func roundTrip() throws {

        let values = ["proTier": "lifetime", "alarmCount": "3"]
        let payload = try RequestMetadata.encode(values)

        let record = CKRecord(recordType: RecordType.requestMetadata,
                              recordID: CKRecord.ID(recordName: "meta_req1"))

        record[FieldKey.request] = CKRecord.Reference(recordID: CKRecord.ID(recordName: "req1"), action: .deleteSelf)
        record[FieldKey.payload] = payload

        let decoded = try #require(RequestMetadata(record: record))

        #expect(decoded.values == values)
        #expect(decoded.requestID.recordName == "req1")
    }

    /// Throws rather than truncating: silently losing part of a developer's diagnostic payload is
    /// worse than a clear error at the call site.
    @Test("An oversized payload throws instead of truncating")
    func oversizedPayloadThrows() {

        let huge = [String(repeating: "k", count: 100): String(repeating: "v", count: 70_000)]

        #expect(throws: FeedbackError.self) { try RequestMetadata.encode(huge) }
    }

    @Test("Unparseable payloads degrade to empty rather than dropping the record")
    func malformedPayload() throws {

        let record = CKRecord(recordType: RecordType.requestMetadata,
                              recordID: CKRecord.ID(recordName: "meta_req1"))

        record[FieldKey.request] = CKRecord.Reference(recordID: CKRecord.ID(recordName: "req1"), action: .deleteSelf)
        record[FieldKey.payload] = "not json"

        let decoded = try #require(RequestMetadata(record: record))

        #expect(decoded.values.isEmpty)
    }

    @Test("A record with no request reference is rejected")
    func missingReference() {

        let record = CKRecord(recordType: RecordType.requestMetadata,
                              recordID: CKRecord.ID(recordName: "meta_req1"))

        #expect(RequestMetadata(record: record) == nil)
    }
}


/// The pointer to a pinned workaround lives on `Request`, which its creator can write. These are the
/// checks that stop a pointer aimed anywhere else from rendering as the developer's words.
@Suite("Pinned workaround resolution")
struct WorkaroundResolutionTests {

    private let requestID = CKRecord.ID(recordName: "req1")

    private func request(pointingAt name: String) throws -> FeedbackRequest {

        let record = CKRecord(recordType: RecordType.request, recordID: requestID)

        record[FieldKey.workaroundCommentID] = name

        return try #require(FeedbackRequest(record: record))
    }

    private func comment(_ name: String, type: String, on parent: String = "req1") throws -> FeedbackComment {

        let record = CKRecord(recordType: type, recordID: CKRecord.ID(recordName: name))

        record[FieldKey.request] = CKRecord.Reference(recordID: CKRecord.ID(recordName: parent), action: .deleteSelf)
        record[FieldKey.body] = "Pull to refresh after waking."

        return try #require(FeedbackComment(record: record))
    }

    @Test("A developer reply on this request resolves")
    func resolves() throws {

        let pinned = try comment("dev1", type: RecordType.devComment)
        let comments = [try comment("user1", type: RecordType.comment), pinned]

        #expect(CommentService.workaround(for: try request(pointingAt: "dev1"), in: comments) == pinned)
    }

    @Test("A pointer at a user's comment renders nothing")
    func userCommentRejected() throws {

        let comments = [try comment("user1", type: RecordType.comment)]

        #expect(CommentService.workaround(for: try request(pointingAt: "user1"), in: comments) == nil)
    }

    @Test("A pointer at another request's developer reply renders nothing")
    func otherRequestRejected() throws {

        let comments = [try comment("dev1", type: RecordType.devComment, on: "req2")]

        #expect(CommentService.workaround(for: try request(pointingAt: "dev1"), in: comments) == nil)
    }

    @Test("No pointer, no workaround")
    func emptyPointer() throws {

        let comments = [try comment("dev1", type: RecordType.devComment)]

        #expect(CommentService.workaround(for: try request(pointingAt: ""), in: comments) == nil)
    }
}


@Suite("Broadcast recipients")
struct BroadcastRecipientTests {

    @Test("Followers and voters are merged, exclusions and empty IDs removed")
    func recipients() {

        let recipients = ModerationService.broadcastRecipients(followers: ["_a", "_b", ""],
                                                               voters: ["_b", "_c", "_author", "_dev"],
                                                               excluding: ["_author", "_dev"])

        #expect(recipients == ["_a", "_b", "_c"])
    }
}
