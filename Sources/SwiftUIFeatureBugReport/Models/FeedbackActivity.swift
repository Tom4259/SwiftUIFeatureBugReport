//
//  FeedbackActivity.swift
//  SwiftUIFeatureBugReport
//

import CloudKit
import Foundation

/// A developer-authored notice addressed to one user.
///
/// `requestTitle` and `message` are denormalised **specifically so a push subscription can substitute
/// them server-side** - `alertLocalizationArgs` takes field names and CloudKit fills in their values
/// from the triggering record (§8). `message` is always display-ready text composed by the portal,
/// never a raw enum value.
public struct FeedbackActivity: Identifiable, Sendable, Hashable {

    public let id: CKRecord.ID
    public let requestID: CKRecord.ID
    public let recipientID: String
    public let kind: ActivityKind
    public let requestTitle: String
    public let message: String
    public let createdAt: Date

    public init?(record: CKRecord) {

        guard record.recordType == RecordType.activity,
              let reference = record[FieldKey.request] as? CKRecord.Reference else { return nil }

        self.id = record.recordID
        self.requestID = reference.recordID
        self.recipientID = record[FieldKey.recipientID] as? String ?? ""
        self.kind = ActivityKind(rawValue: record[FieldKey.kind] as? String ?? "") ?? .status
        self.requestTitle = record[FieldKey.requestTitle] as? String ?? ""
        self.message = record[FieldKey.message] as? String ?? ""
        self.createdAt = record.creationDate ?? .now
    }
}
