// swift-tools-version: 6.2
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "SwiftUIFeatureBugReport",
    // The source language of every string in this package. Note that it does not change where they
    // resolve from: `Text` and `String(localized:)` both look in `Bundle.main`, so the keys land in
    // the *host app's* catalogue and are translated there. See README > Localisation.
    defaultLocalization: "en-GB",
    platforms: [
        .iOS(.v17),
        .macOS(.v14)
    ],
    products: [
        .library(
            name: "SwiftUIFeatureBugReport",
            targets: ["SwiftUIFeatureBugReport"]
        ),
    ],
    targets: [
        .target(
            name: "SwiftUIFeatureBugReport",
            resources: [
                // Folded into the host app's privacy report by Xcode. See README > Privacy.
                .copy("PrivacyInfo.xcprivacy")
            ]
        ),
        .testTarget(
            name: "SwiftUIFeatureBugReportTests",
            dependencies: ["SwiftUIFeatureBugReport"]
        ),
    ]
)
