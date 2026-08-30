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
            .status: "ACTIVITY_STATUS",
            .comment: "ACTIVITY_COMMENT",
            .complete: "ACTIVITY_COMPLETE",
            .imageApproved: "ACTIVITY_IMAGE_APPROVED",
            .imageRejected: "ACTIVITY_IMAGE_REJECTED",
            .shipped: "ACTIVITY_SHIPPED"
        ]

        for (kind, key) in expected {

            #expect(kind.localizationKey == key)
        }
    }
}
