# SwiftUIFeatureBugReport

An in-app feedback board for SwiftUI apps, backed entirely by your own CloudKit container.

Users can submit bugs and feature requests, vote, follow updates, reply, report content and browse a
roadmap. Developers get a triage portal for status, labels, replies, image moderation and deletion.
The package author receives no data and has no access to your container.

## Requirements

- iOS 17+ or macOS 14+
- Xcode 26+ (the package uses Swift tools 6.2)
- A paid Apple Developer account
- App Store or TestFlight distribution for production push notifications

## Installation

In Xcode, choose **File → Add Package Dependencies…**, enter:

```
https://github.com/Tom4259/SwiftUIFeatureBugReport
```

Use the **Up to Next Major Version** rule starting at `2.0.0`.

Or add the package in `Package.swift`:

```swift
.package(
    url: "https://github.com/Tom4259/SwiftUIFeatureBugReport",
    from: "2.0.0"
)
```

## Add the board

```swift
import SwiftUIFeatureBugReport

let configuration = FeedbackConfiguration(
    containerIdentifier: "iCloud.com.yourcompany.yourapp",
    developerUserRecordIDs: ["_abc123…"],
    reportThreshold: 3,
    allowComments: true,
    allowImageAttachments: true
)

NavigationStack {
    FeedbackBoardView(configuration: configuration)
}
```

`developerUserRecordIDs` controls who sees the developer portal. CloudKit's `dev` role separately
authorizes developer writes; configure both if you use the portal.

## CloudKit setup

Budget about 20 minutes. Complete these steps in order.

### 1. Add capabilities

In your app target, open **Signing & Capabilities**:

1. Add **iCloud**, enable **CloudKit**, and select or create your container.
2. Add **Push Notifications**.

The identifier passed to `FeedbackConfiguration` must appear in the app's iCloud entitlement.

### 2. Import a schema

Choose one file from the repository root:

- `Schema.ckdb`: user replies enabled.
- `Schema-NoComments.ckdb`: users cannot reply; developer replies still work.

Create a management token in CloudKit Console under **Settings → Tokens & Keys**, then:

```sh
xcrun cktool save-token --type management
xcrun cktool get-teams

xcrun cktool validate-schema --team-id <TEAM> --container-id <CONTAINER> \
  --environment development --file Schema.ckdb

xcrun cktool import-schema --team-id <TEAM> --container-id <CONTAINER> \
  --environment development --file Schema.ckdb
```

Use `Schema-NoComments.ckdb` in both commands when comments are disabled. Do not edit the checked-in
schemas during installation.

### 3. Configure developer access

Skip this step if you do not need the developer portal.

Run the app once while signed in to iCloud, then obtain your CloudKit user record ID:

```swift
let container = CKContainer(identifier: "iCloud.com.yourcompany.yourapp")
let id = try await container.userRecordID()
print(id.recordName)
```

In CloudKit Console, open the public database's built-in `Users` record, find that ID, and add the
`dev` role. Put the same ID in `developerUserRecordIDs`.

Repeat this for every developer account. If the IDs are hard-coded in the app, adding another one
requires a new build.

### 4. Add notification strings

Add these keys to the host app's `Localizable.xcstrings` or `Localizable.strings`:

```text
"ACTIVITY_TITLE"          = "%@";
"ACTIVITY_STATUS"         = "Status updated";
"ACTIVITY_COMMENT"        = "New reply";
"ACTIVITY_COMPLETE"       = "Marked complete";
"ACTIVITY_IMAGE_APPROVED" = "Your image was approved";
"ACTIVITY_IMAGE_REJECTED" = "Your image was removed";
"ACTIVITY_SHIPPED"        = "Shipped";
"NEW_REQUEST"             = "New feedback";
```

Only `ACTIVITY_TITLE` contains a placeholder. Notification permission is requested after the user's
first successful submission rather than when the board opens.

### 5. Match the configuration to the schema

```swift
FeedbackConfiguration(
    containerIdentifier: "iCloud.com.yourcompany.yourapp",
    developerUserRecordIDs: ["_abc123…"],
    reportThreshold: 3,
    allowComments: true,          // use Schema.ckdb
    allowImageAttachments: true
)
```

Set `allowComments: false` when using `Schema-NoComments.ckdb`.

### 6. Deploy before release

Test in CloudKit's Development environment first. When ready:

1. In CloudKit Console, choose **Deploy Schema Changes**.
2. Add the `dev` role to developer user records in Production as well.
3. Ensure distributed builds use the Production CloudKit environment.
4. Verify a request, vote and notification in Production before release.

Use Production for real feedback. Switch back to Development for schema changes and destructive
testing.

See [CloudKit setup](Docs/CloudKit-Setup.md) for environment details, verification commands and
troubleshooting.

## Sharing a store

Create one store when several screens appear in the same app. This avoids repeating board and tally
queries:

```swift
@State private var feedback = FeedbackStore(configuration: configuration)

TabView {
    FeedbackBoardView(store: feedback)
        .tabItem { Label("Feedback", systemImage: "bubble.left") }

    RoadmapView(store: feedback)
        .tabItem { Label("Roadmap", systemImage: "map") }
}
```

Every configuration-based entry view initializes its own store. Store-based views share one
idempotent startup operation, so they can safely appear together.

Open a prefilled form from a crash handler, settings screen or support action:

```swift
FeedbackFormView(
    store: feedback,
    prefill: FeedbackPrefill(
        title: "Alarm didn't fire",
        type: .bug,
        metadata: [
            "lastAlarmID": alarm.id,
            "schedulerState": scheduler.stateDescription
        ]
    )
)
```

Metadata is disclosed before submission and stored in a separate record readable only by its creator
and the developer role.

## Navigation

`FeedbackBoardView` uses the navigation container supplied by your app. On iOS, place it inside a
`NavigationStack`. On macOS it provides its own side-by-side board and detail layout without nesting
a `NavigationSplitView`.

Other public views accept `embedsNavigationStack: Bool = true`. Set it to `false` when placing the
view inside a navigation stack your app already owns.

## Testing

```sh
swift test
```

The test suite requires no CloudKit account or network connection.

## Detailed documentation

- [CloudKit setup and environments](Docs/CloudKit-Setup.md)
- [Schema and permissions](Docs/Schema-and-Permissions.md)
- [Notifications](Docs/Notifications.md)
- [Privacy guidance](Docs/Privacy.md)
- [Upgrading from 1.x](Docs/Migration-from-1.x.md)
- [Troubleshooting](Docs/Troubleshooting.md)

## License

MIT. See [LICENSE](LICENSE).
