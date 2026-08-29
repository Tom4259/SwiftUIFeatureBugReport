//
//  DeviceEnvironment.swift
//  SwiftUIFeatureBugReport
//

import Foundation

/// The device and build a request came from, as five real fields rather than one formatted string.
///
/// Separate fields because each one is queryable: the portal filters the queue by `appVersion`, which
/// a blob of text cannot answer.
///
/// All five are written onto `Request` and are therefore world-readable. Deliberate: device model,
/// OS and app version appear on the face of every public issue tracker and are not sensitive. Only
/// developer-supplied metadata gets the private `RequestMetadata` record.
public struct DeviceEnvironment: Sendable, Hashable {

    public let appVersion: String
    public let buildNumber: String
    public let osVersion: String
    public let deviceModel: String
    public let platform: String

    public init(appVersion: String,
                buildNumber: String,
                osVersion: String,
                deviceModel: String,
                platform: String) {

        self.appVersion = appVersion
        self.buildNumber = buildNumber
        self.osVersion = osVersion
        self.deviceModel = deviceModel
        self.platform = platform
    }

    /// "1.17.4 (291)", or just "1.17.4" when there is no build number.
    ///
    /// Every TestFlight tester on a given version reports the same `appVersion`, so the build is the
    /// only thing that tells their reports apart - which is exactly when you need to.
    public var versionLabel: String {

        buildNumber.isEmpty || buildNumber == "Unknown" ? appVersion : "\(appVersion) (\(buildNumber))"
    }

    /// Ordered for display in the metadata disclosure sheet (§9.3).
    public var disclosureEntries: [(label: LocalizedStringResource, value: String)] {

        [
            ("Device", deviceModel),
            ("Operating system", osVersion),
            ("Platform", platform),
            ("App version", appVersion),
            ("Build", buildNumber)
        ]
    }
}
