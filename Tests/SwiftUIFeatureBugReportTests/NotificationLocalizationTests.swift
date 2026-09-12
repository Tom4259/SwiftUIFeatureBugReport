//
//  NotificationLocalizationTests.swift
//  SwiftUIFeatureBugReportTests
//

import Testing

@testable import SwiftUIFeatureBugReport

@Suite("Push notification localization keys")
struct NotificationLocalizationTests {

    @Test("Every activity kind has the documented body key")
    func keys() {

        let expected: [ActivityKind: String] = [
            .status: "Status updated",
            .comment: "New reply",
            .complete: "Marked complete",
            .imageApproved: "Your image was approved",
            .imageRejected: "Your image was removed",
            .shipped: "Shipped"
        ]

        for (kind, key) in expected {

            #expect(kind.localizationKey == key)
        }
    }

    /// The point of the rewrite. A push key is resolved against the *host app's* bundle and a missing
    /// entry is displayed verbatim, so a key that is not already readable English is a notification
    /// reading `ACTIVITY_COMMENT` in every app that has not copied the tokens into a catalogue.
    @Test("No key is a machine token")
    func keysReadAsEnglish() {

        var keys = ActivityKind.allCases.map(\.localizationKey)

        keys.append(ActivityService.developerNotificationTitle)
        keys.append(ActivityService.developerNotificationBody)

        for key in keys {

            #expect(key.first?.isUppercase == true, "\(key) should read as a sentence")
            #expect(key != key.uppercased(), "\(key) looks like a SCREAMING_CASE token")
            #expect(!key.contains("_"), "\(key) looks like a SCREAMING_CASE token")
        }
    }

    /// The one key that is a format string rather than a sentence: the activity title is the user's own
    /// request title, so there is no English in it for a translator to reach.
    @Test("The activity title is pure substitution")
    func titleFormat() {

        #expect(ActivityService.activityTitleFormat == "%@")
    }
}
