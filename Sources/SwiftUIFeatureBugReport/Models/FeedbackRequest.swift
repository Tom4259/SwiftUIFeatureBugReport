//
//  FeedbackRequest.swift
//  SwiftUIFeatureBugReport
//

import CloudKit
import Foundation

/// Fields are mapped by hand rather than through `Codable`. A schema mismatch should be something
/// you fix at the call site, not a decode surprise at runtime.
///
/// **Every field is written on create, always.** CloudKit does not match records where a field was
/// never written, so an absent field silently drops the record out of any `field == value` query -
/// which is also why none of the state fields are booleans.
public struct FeedbackRequest: Identifiable, Sendable, Hashable {

    public let id: CKRecord.ID
    public var title: String
    public var body: String
    public var type: FeedbackType
    public var status: RequestStatus
    public var moderation: ModerationState
    public var imageState: ImageState
    public var labels: [String]

    /// The app version this shipped fixed in, once a developer has set it. Empty until then.
    ///
    /// Not to be confused with `environment.appVersion`, which is the version the request was
    /// reported from.
    public var resolvedInVersion: String
    public let creatorID: String
    public let environment: DeviceEnvironment
    public var lastActivityAt: Date
    public let createdAt: Date

    /// Up to `maximumImages`. Populated only by the detail view, which is the one place that fetches
    /// the assets - a list query must never pull them.
    public var imageURLs: [URL] = []

    /// Capped client-side rather than in the schema, so raising it later is not a migration.
    public static let maximumImages = 3

    public init?(record: CKRecord) {

        guard record.recordType == RecordType.request else { return nil }

        self.id = record.recordID
        self.title = record[FieldKey.title] as? String ?? ""
        self.body = record[FieldKey.body] as? String ?? ""
        self.type = FeedbackType(rawValue: record[FieldKey.type] as? String ?? "") ?? .bug
        self.status = RequestStatus(rawValue: record[FieldKey.status] as? String ?? "") ?? .open
        self.moderation = ModerationState(rawValue: record[FieldKey.moderation] as? String ?? "") ?? .visible
        self.imageState = ImageState(rawValue: record[FieldKey.imageState] as? String ?? "") ?? .none
        self.labels = record[FieldKey.labels] as? [String] ?? []
        self.resolvedInVersion = record[FieldKey.resolvedInVersion] as? String ?? ""
        self.creatorID = record[FieldKey.creatorID] as? String ?? ""
        self.lastActivityAt = record[FieldKey.lastActivityAt] as? Date ?? record.creationDate ?? .now
        self.createdAt = record.creationDate ?? .now

        self.environment = DeviceEnvironment(
            appVersion: record[FieldKey.appVersion] as? String ?? "",
            buildNumber: record[FieldKey.buildNumber] as? String ?? "",
            osVersion: record[FieldKey.osVersion] as? String ?? "",
            deviceModel: record[FieldKey.deviceModel] as? String ?? "",
            platform: record[FieldKey.platform] as? String ?? ""
        )
    }

    /// Writes every field this type owns onto `record`, leaving `images` alone - the assets are
    /// managed separately because list queries must never fetch them.
    func apply(to record: CKRecord) {

        record[FieldKey.title] = title
        record[FieldKey.body] = body
        record[FieldKey.type] = type.rawValue
        record[FieldKey.status] = status.rawValue
        record[FieldKey.moderation] = moderation.rawValue
        record[FieldKey.imageState] = imageState.rawValue
        record[FieldKey.labels] = labels
        record[FieldKey.resolvedInVersion] = resolvedInVersion
        record[FieldKey.creatorID] = creatorID
        record[FieldKey.appVersion] = environment.appVersion
        record[FieldKey.buildNumber] = environment.buildNumber
        record[FieldKey.osVersion] = environment.osVersion
        record[FieldKey.deviceModel] = environment.deviceModel
        record[FieldKey.platform] = environment.platform
        record[FieldKey.lastActivityAt] = lastActivityAt
    }

    /// The keys a list query should ask for - everything except `image`.
    static var listDesiredKeys: [String] {

        [
            FieldKey.title, FieldKey.body, FieldKey.type, FieldKey.status,
            FieldKey.moderation, FieldKey.imageState, FieldKey.labels, FieldKey.creatorID,
            FieldKey.resolvedInVersion,
            FieldKey.appVersion, FieldKey.buildNumber, FieldKey.osVersion,
            FieldKey.deviceModel, FieldKey.platform, FieldKey.lastActivityAt
        ]
    }

    /// Search results only need enough to render a row and vote from it (§6.2).
    static var searchDesiredKeys: [String] {

        [FieldKey.title, FieldKey.status, FieldKey.type, FieldKey.moderation, FieldKey.resolvedInVersion]
    }

    // `Equatable` and `Hashable` are both synthesised, deliberately.
    //
    // An earlier version compared on `id` alone. That made an edited request compare equal to its own
    // previous value, so SwiftUI treated every in-place change - a label removed, a status set, an
    // image approved - as no change at all and never redrew. Identity-based equality on a value type
    // that gets mutated in place is a trap; if you need identity, compare `id` explicitly.
}
