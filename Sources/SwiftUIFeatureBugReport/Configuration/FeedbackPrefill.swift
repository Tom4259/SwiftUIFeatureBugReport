//
//  FeedbackPrefill.swift
//  SwiftUIFeatureBugReport
//

import Foundation

/// Opens the form part-filled - from a crash handler, a shake gesture, or a settings row.
///
/// Title and body remain **required at submit** regardless of what is prefilled; the submit button
/// stays disabled until both are non-empty.
public struct FeedbackPrefill: Sendable {

    public var title: String?
    public var body: String?
    public var type: FeedbackType?

    /// Developer-supplied key/value pairs stored on the private `RequestMetadata` record.
    ///
    /// Shown to the user in full before submission (there is no hidden collection here) but not
    /// readable by other users of the app.
    public var metadata: [String: String]

    public init(title: String? = nil,
                body: String? = nil,
                type: FeedbackType? = nil,
                metadata: [String: String] = [:]) {

        self.title = title
        self.body = body
        self.type = type
        self.metadata = metadata
    }
}
