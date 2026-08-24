//
//  FeedbackComment.swift
//  SwiftUIFeatureBugReport
//

import CloudKit
import Foundation

/// One entry in a request's timeline, from either `Comment` or `DevComment`.
///
/// Developer authorship comes from the **record type**, never a field. `DevComment` is the only
/// record type with `dev: CREATE`, so a user cannot write one - which is what makes the badge
/// unspoofable. (v1 used a `"User: "` body prefix, which anyone could forge.)
public struct FeedbackComment: Identifiable, Sendable, Hashable {

    public let id: CKRecord.ID
    public let requestID: CKRecord.ID
    public let body: String
    public let creatorID: String
    public let isDeveloper: Bool
    public let createdAt: Date

    public init?(record: CKRecord) {

        switch record.recordType {

        case RecordType.comment: self.isDeveloper = false
        case RecordType.devComment: self.isDeveloper = true
        default: return nil
        }

        guard let reference = record[FieldKey.request] as? CKRecord.Reference else { return nil }

        self.id = record.recordID
        self.requestID = reference.recordID
        self.body = record[FieldKey.body] as? String ?? ""
        self.creatorID = record[FieldKey.creatorID] as? String ?? ""
        self.createdAt = record.creationDate ?? .now
    }
}
