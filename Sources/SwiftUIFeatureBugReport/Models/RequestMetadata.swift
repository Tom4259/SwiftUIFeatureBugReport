//
//  RequestMetadata.swift
//  SwiftUIFeatureBugReport
//

import CloudKit
import Foundation

/// Developer-supplied key/value pairs, kept off `Request` so they are not world-readable.
///
/// `payload` is one JSON string rather than real CloudKit fields **on purpose**: if integrator
/// metadata became columns, every integrator would need a different schema and the shipped
/// `Schema.ckdb` would stop working for everyone.
///
/// The permission grant on this type is `_icloud: CREATE` **without** `_world: READ` - create-without-
/// read is what makes the metadata genuinely private rather than merely hidden in the UI.
public struct RequestMetadata: Sendable, Hashable {

    /// CloudKit rejects records over 1 MB; 64 KB of metadata is already far past reasonable, so this
    /// throws rather than truncating - silently losing a developer's diagnostic payload is worse than
    /// a clear error at the call site.
    static let maximumPayloadBytes = 64 * 1024

    public let requestID: CKRecord.ID
    public let values: [String: String]

    public init(requestID: CKRecord.ID, values: [String: String]) {

        self.requestID = requestID
        self.values = values
    }

    public init?(record: CKRecord) {

        guard record.recordType == RecordType.requestMetadata,
              let reference = record[FieldKey.request] as? CKRecord.Reference else { return nil }

        self.requestID = reference.recordID

        guard let payload = record[FieldKey.payload] as? String,
              let data = payload.data(using: .utf8),
              let decoded = try? JSONDecoder().decode([String: String].self, from: data) else {

            self.values = [:]
            return
        }

        self.values = decoded
    }

    static func encode(_ values: [String: String]) throws -> String {

        let data = try JSONEncoder().encode(values)

        guard data.count <= maximumPayloadBytes else {

            throw FeedbackError.metadataTooLarge(bytes: data.count, limit: maximumPayloadBytes)
        }

        return String(decoding: data, as: UTF8.self)
    }
}
