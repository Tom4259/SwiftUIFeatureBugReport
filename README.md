# SwiftUIFeatureBugReport

An in-app feedback board. Bug reports and feature requests, with voting, replies, a roadmap and a
developer triage portal. Running entirely on **your own CloudKit container**, under **your own Apple
Developer account**.

There is no server to run, no API key to ship, and no third party in the loop. The author of this
package receives nothing and has no access to any integrator's data.

> **Version 2.0 is a ground-up rebuild.** The GitHub Issues backend is gone. See
> [Upgrading from 1.x](#8-upgrading-from-1x).

1. [What it is](#1-what-it-is)
2. [Installation](#2-installation)
3. [Requirements](#3-requirements)
4. [Setup](#4-setup): the CloudKit work, 8 steps
5. [Finding your user record ID](#5-finding-your-user-record-id)
6. [Index checklist](#6-index-checklist)
7. [Privacy](#7-privacy): written to lift into your own policy
8. [Upgrading from 1.x](#8-upgrading-from-1x)

---

## 1. What it is

Seven SwiftUI views over eight CloudKit record types in your app's **public** database:

| View | Audience | What it does |
|---|---|---|
| `FeedbackBoardView` | everyone | Browse, filter by type, sort by votes or recency, search, vote inline, open the form |
| `RequestDetailView` | everyone | Full text, images, labels, status, merged reply timeline, vote, follow, report; the creator gets edit and mark-complete |
| `FeedbackFormView` | everyone | Type, title, body, search-before-submit, up to three images (optional), full disclosure of what gets sent |
| `RoadmapView` | everyone | What's coming, grouped by status; what shipped, grouped by the version it shipped in |
| `UpdatesView` | everyone | Activity on requests you created or voted for |
| `MyDataView` | everyone | Counts of your requests, votes, replies and reports, plus a real deletion |
| `DeveloperPortalView` | you | Open / Reported / Images / All queues, search, reported items with category breakdown, pending images, version filter, status, labels, replies, hide, delete, block |

Every view is standalone and takes `embedsNavigationStack: Bool = true`. Leave it on when presenting
into something with no navigation of its own (a sheet, a split view's detail column). Turn it **off**
when pushing onto a stack your app already owns. A `NavigationStack` nested inside another stack's
destination makes SwiftUI compare the two paths against each other, and it traps when their element
types differ.

```swift
import SwiftUIFeatureBugReport

let configuration = FeedbackConfiguration(
    containerIdentifier: "iCloud.com.yourcompany.yourapp",
    developerUserRecordIDs: ["_abc123…"],   // see step 4
    reportThreshold: 3,
    allowComments: true,                    // see step 5
    allowImageAttachments: true
)

FeedbackBoardView(configuration: configuration)
```

Sharing one store across several screens avoids each of them reloading the same vote tallies:

```swift
@State private var feedback = FeedbackStore(configuration: configuration)

TabView {
    FeedbackBoardView(store: feedback).tabItem { Label("Feedback", systemImage: "bubble.left") }
    RoadmapView(store: feedback).tabItem { Label("Roadmap", systemImage: "map") }
}
```

Opening the form pre-filled. From a crash handler, a shake gesture, or a settings row:

```swift
FeedbackFormView(
    store: feedback,
    prefill: FeedbackPrefill(
        title: "Alarm didn't fire",
        type: .bug,
        metadata: ["lastAlarmID": alarm.id, "schedulerState": scheduler.stateDescription]
    )
)
```

`metadata` is stored on a **private** record only you and the submitter can read. Title and body stay
required at submit regardless of what was prefilled.

---

## 2. Installation

In Xcode: **File → Add Package Dependencies…**, then paste:

```
https://github.com/Tom4259/SwiftUIFeatureBugReport
```

Or in a `Package.swift`:

```swift
dependencies: [
    .package(url: "https://github.com/Tom4259/SwiftUIFeatureBugReport", from: "2.0.0")
]
```

Adding the package is the easy part. **Budget 20–30 minutes for the CloudKit setup in section 4**.
Most of it is Dashboard work that no package can do for you, and skipping a step tends to surface
later as a runtime error that does not name the step you missed.

---

## 3. Requirements

- iOS 17+ / macOS 14+
- **Xcode 26 or newer.** `Package.swift` declares `swift-tools-version: 6.2`, so older Xcode versions
  fail to read the manifest at all, before any of your own code is compiled.
- **A paid Apple Developer account.** CloudKit containers cannot be created without one.
- **App Store distribution.** Push notifications from CloudKit need the standard push entitlement;
  Developer ID / outside-the-App-Store distribution is not supported here.

Both platforms are first-class. The image picker, refresh affordance, row actions, navigation shape
and portal layout each branch properly rather than degrading on the Mac.

---

## 4. Setup

Do these in order. Steps 1–3 are pure setup; from step 4 on you need the app running.

### Step 1. Create the CloudKit container

In Xcode, select your app target → **Signing & Capabilities** → **+ Capability** → **iCloud**. Tick
**CloudKit**, then **+** under Containers and create one, conventionally
`iCloud.<your.bundle.identifier>`.

### Step 2. Add Push Notifications

Same screen → **+ Capability** → **Push Notifications**. Without it, subscriptions register but no
notification is ever delivered.

> ⚠️ **The container identifier you pass to `FeedbackConfiguration` must be listed in your app's
> iCloud entitlement.** If it is not, `CKContainer(identifier:)` traps and your app dies on launch
> before any of this package's error handling runs. This is CloudKit's own check, not something the
> package can catch or report. If your app crashes immediately at startup after integrating, this is
> almost always why.

### Step 3. Import the schema

`Schema.ckdb` at the repo root defines all eight record types **and the `dev` security role**. You do
not need to create anything in the Dashboard first. `CREATE ROLE dev;` is in the file.

Schema commands need a **management** token. Get one from the
[CloudKit Console](https://icloud.developer.apple.com/dashboard/) → **Settings → Tokens & Keys →
Management Tokens**, then:

```
xcrun cktool save-token --type management     # prompts for the token
xcrun cktool get-teams                        # confirms the token and shows your team ID
```

```
xcrun cktool validate-schema --team-id <TEAM> --container-id <CONTAINER> \
  --environment development --file Schema.ckdb

xcrun cktool import-schema --team-id <TEAM> --container-id <CONTAINER> \
  --environment development --file Schema.ckdb
```

Confirm it landed by exporting and checking the record types are present:

```
xcrun cktool export-schema --team-id <TEAM> --container-id <CONTAINER> \
  --environment development --output-file Schema.ckdb
```

> Use `export-schema` to verify rather than `query-records`. Record operations need a separate **user**
> token, and reaching for one just to check an import is wasted effort: the export uses the
> management token you already have, and it shows the schema as CloudKit actually stored it.

`Schema.ckdb` is a real `export-schema` output. **Do not hand-edit it.** To change the schema, edit it
in the Dashboard or import a modified copy, then re-export over the file. Two rules the exported
dialect enforces, if you ever do write one by hand: custom roles must be declared with `CREATE ROLE`
in the file itself, and granting to an undeclared role fails validation with *"Record type permission
uses undefined role"*. Which looks like a missing Dashboard role but is not.

### Step 4. Find your user record ID and add yourself to `dev`

The role needs a user, and a user record only exists once the app has been run at least once while
signed in to iCloud.

1. Build and run your app on a device or simulator signed in to your iCloud account.
2. Print your record ID:

   ```swift
   let container = CKContainer(identifier: "iCloud.com.yourcompany.yourapp")
   let id = try await container.userRecordID()
   print("CloudKit user record ID:", id.recordName)   // _abc123…
   ```

3. Add that record ID to the `dev` role. **This is not on the Security Roles page** - that page assigns
   record types to a role, which the schema import already did. Membership lives on the user's own
   record, in the `roles` field of the built-in `Users` type:

   CloudKit Console → your container → **Development** → **Data** → **Records** → Database **Public**,
   Zone `_defaultZone`, Record Type **Users** → find the record whose name is your ID → edit `roles`
   and add `dev`.

   The user record only exists once that account has used the container at least once, so run the app
   before looking for it.
4. Put the same string into `FeedbackConfiguration.developerUserRecordIDs`.

These are two separate things and you need both. The Dashboard role is what authorises your writes;
the configuration list is what shows you the portal. With only the second, the portal appears and
every action inside it fails.

The list is a list on purpose: a team can have more than one developer, and you can add a second
Apple Account later without shipping an update.

### Step 5. Optional features

Two things you can switch off, both because they cost you something real rather than because they are
matters of taste.

**`allowComments: false`**. Users cannot start a reply thread on their own request. Every reply is a
message someone expects an answer to, and not every developer wants that channel. **You can still
reply to them**; only the user side closes.

If you turn this off, you can go further and **omit the `Comment` record type from your schema
entirely**. Delete the whole `RECORD TYPE Comment (…);` block from `Schema.ckdb` before importing.
The package never queries that record type when the flag is `false`, so nothing breaks.

This matters because the flag on its own is a **UI convention, not a security boundary.** CloudKit
cannot express "only the request's creator may comment", so a determined user with the CloudKit API
could still write a `Comment` record. Leaving the record type out of the schema is what makes it
actually enforced. Keep `DevComment` either way: that is how you reply.

**`allowImageAttachments: false`**. No screenshot picker in the form, and the package refuses to
attach assets even if a call site passes them. Images are the bulk of a public container's storage,
and accepting user-submitted pictures raises the App Review moderation bar considerably. Text-only is
a legitimate risk decision.

Unlike comments, `images` is a *field* on `Request` rather than its own record type, so it stays in
the schema and simply goes unused. Images attached before you turned the flag off still display.

**What you cannot switch off, deliberately:** reporting, blocking and delete-my-data. Apple's
user-generated content guideline requires filtering, reporting and blocking, and deletion is its own
requirement. A flag there would be a switch for shipping a rejectable build, so there isn't one.

### Step 6. Deploy the schema to Production

CloudKit Dashboard → **Deploy Schema Changes**.

Records saved in Development auto-create their record types. **Production does not.** Skip this and
your App Store build fails in a way that looks nothing like a missing schema.

### Step 6a. Your own builds will not see App Store feedback

CloudKit picks the environment from how the app was signed. **An Xcode build talks to Development; an
App Store or TestFlight build talks to Production.** So running your app from Xcode shows you your own
test records, never the feedback real users are sending. This catches people out badly, because an
empty Production board and an empty Development board look exactly the same.

Three ways round it, cheapest first:

**Add a Production scheme.** Put `com.apple.developer.icloud-container-environment` = `Production` in a
second entitlements file, point a new build configuration and scheme at it, and run that scheme when
you want to moderate live feedback. This works from an ordinary debug build, on device and in the
Simulator. Leave `aps-environment` as `development` - push and CloudKit are separate keys.

**Install your own TestFlight build.** Also Production, no configuration at all, but no debugger and a
slow loop.

**CloudKit Console or `cktool`.** Both reach Production today. Neither writes `Activity` records, so
anything you change there is **silent** - the user gets no notification. Fine in an emergency, wrong as
a routine tool.

Whichever you choose, set `FeedbackConfiguration.environment` to match. The portal shows a warning
banner when it is `.development`, and nothing at all when it is `.production` - the point is to catch
the mistake, not to decorate every triage session:

```swift
#if PRODUCTION_CLOUDKIT
environment: .production
#else
environment: .development
#endif
```

The default (`Debug` to Development, `Release` to Production) is right unless you force the
entitlement. Nothing in the app can read which environment CloudKit actually chose, so this is a label
you set rather than a value the package detects, which is why it is worth setting honestly.

### Step 6b. How releases flow through the board

Two statuses cover the gap between "fixed" and "people can install it":

- **Update Pending**. The fix is written but the build is not live. Nobody can get it yet, so nothing
  claims it shipped.
- **Complete**. The build is out. The portal prefills **Fixed in version** with whatever build it is
  running (editable, for when you are testing 2.2 while shipping 2.1).

Once set, that version appears wherever the request does: most usefully in search-before-submit,
where someone about to file a duplicate reads **"Fixed in 2.1"** rather than just "Fixed". That one
line is what stops *"then why is it still broken for me?"* arriving as a support message.

`RoadmapView` groups shipped requests by that version, newest first, so it doubles as a what-changed
list for anyone who has not updated. Version ordering uses numeric comparison, so `2.10` correctly
sorts above `2.9`.

### Step 7. Add the push notification strings

Push text comes from `alertLocalizationKey` resolved against **your app's** bundle, not this
package's, so these keys have to live in your own string table:

```
"ACTIVITY_TITLE"          = "%@";
"ACTIVITY_STATUS"         = "Status updated";
"ACTIVITY_COMMENT"        = "New reply";
"ACTIVITY_COMPLETE"       = "Marked complete";
"ACTIVITY_IMAGE_APPROVED" = "Your image was approved";
"ACTIVITY_IMAGE_REJECTED" = "Your image was removed";
"ACTIVITY_SHIPPED"        = "Shipped";
"NEW_REQUEST"             = "New feedback";
```

Only `ACTIVITY_TITLE` takes `%@` - it is the notification **title** and renders the request title. The
rest are bodies and deliberately do not repeat it: "Dark mode" / "New reply" beats "Dark mode" / "Dark
mode has a new reply". Localisation arguments passed to a format with no placeholder are ignored, so
the bodies stay valid.

**If a push arrives showing the raw key** (`ACTIVITY_TITLE`, `NEW_REQUEST`), that key is missing from
your app's string table and iOS falls back to displaying the key itself. Add the keys above and
rebuild. The values are looked up on-device at delivery, so changing wording later needs no
re-registration; only changing a key name or its arguments does.

A `CKSubscription.NotificationInfo` is fixed when the subscription is **created**, not per event, so a
literal `alertBody` would be identical forever. The dynamic part comes from
`alertLocalizationArgs`, which holds *field names*. CloudKit substitutes their values from the
triggering record, server-side.

### Step 8. Pass the configuration

```swift
FeedbackConfiguration(
    containerIdentifier: "iCloud.com.yourcompany.yourapp",
    developerUserRecordIDs: ["_abc123…"],
    reportThreshold: 3,
    allowComments: true,          // step 5
    allowImageAttachments: true,  // step 5
    environment: .development     // step 6a: a label, not a switch
)
```

Notification permission is requested at the moment a user submits their **first** request: never on
first open of the board. There is exactly one system prompt available per install and asking cold
wastes it.

---

## 5. Finding your user record ID

Covered in step 4 above, but worth repeating because it is the step most often skipped:

- The portal is hidden until your record ID is in `developerUserRecordIDs`.
- Developer **writes** are rejected until that same record ID is in the `dev` security role.
- A user record only exists after the app has run once while signed in to iCloud.

If you see *"CloudKit developer role not configured. See README setup step 4"* anywhere in the app,
that is a `.permissionFailure` from CloudKit: your record ID is in `developerUserRecordIDs` but not in
the `dev` role, so the portal shows and its writes are refused. Step 4, part 3.

---

## 6. Index checklist

`Schema.ckdb` already sets all of these, so a clean import gets them right. Worth checking against the
Dashboard anyway if you edited the schema, because every one of them fails **only at runtime**, and
the resulting errors do not name the missing index.

**Per record type: `Request`, `Vote`, `Report`, `Comment`, `DevComment`, `Activity`, `Follow`, `RequestMetadata`:**

- [ ] `___recordID`: **Queryable** (without this you cannot query by reference at all)

**`Users`** (CloudKit's built-in type):

- [ ] `___recordID`: **Queryable**. Without it the Console cannot list user records and reports *"Type
      is not marked indexable: Users"* - which blocks step 4 entirely, since you would have no way to
      find your own user record and put yourself in the `dev` role.

**`Request`:**

- [ ] `title`: Queryable, **Searchable** (the only searchable field; see below)
- [ ] `type`, `status`, `moderation`, `imageState`, `labels`, `resolvedInVersion`: Queryable
- [ ] `creatorID`, `appVersion`, `buildNumber`, `osVersion`, `deviceModel`, `platform`: Queryable
- [ ] `lastActivityAt`: Queryable, **Sortable**
- [ ] `createdTimestamp`: Queryable, **Sortable**

**`Vote`:**

- [ ] `request`: Queryable
- [ ] `createdTimestamp`: Queryable, Sortable

**`Report`:**

- [ ] `request`, `category`: Queryable (`reason` is free text and needs no index)

**`Follow`:**

- [ ] `request`: Queryable
- [ ] `createdTimestamp`: Queryable, Sortable

**`Comment` and `DevComment`:**

- [ ] `request`, `requestCreator`, `creatorID`: Queryable

**`Activity`:**

- [ ] `request`, `recipientID`, `kind`: Queryable
- [ ] `createdTimestamp`: Queryable, Sortable

**`RequestMetadata`:**

- [ ] `request`: Queryable

**Permissions:**

- [ ] `RequestMetadata` grants `_icloud: CREATE` **without** `_world: READ`: Create-without-read is
      what makes developer metadata genuinely private rather than merely hidden in the UI. Verify it
      applies as expected before relying on it.
- [ ] `DevComment` grants `CREATE` to `dev` only. Never to `_icloud`: This is what makes developer
      authorship unspoofable.
- [ ] Your own user record ID is a member of the `dev` role. The role itself comes from the schema;
      its membership does not, and nothing works for you as a developer until you add yourself.
- [ ] If you set `allowComments: false`, the `Comment` record type is **absent** from your schema.
      The flag alone only hides the UI; removing the type is what enforces it. `DevComment` stays.
- [ ] `Vote`, `Report` and `Follow` each grant `READ, WRITE` to `_creator`: Without it a vote is
      permanent, a follow cannot be cancelled, and **"delete my data" cannot remove the user's
      reports**. It fails with a permission error that reads like a misconfigured `dev` role.
- [ ] `resolvedInVersion` is present and **distinct from `appVersion`**. The first is the version a
      request was *fixed* in; the second is the version it was *reported* from. A bug filed on 1.8 may
      ship its fix in 2.1, and conflating them puts the wrong number in front of users.
- [ ] `Request.images` is a `LIST<ASSET>`: Verified against a live container, no fallback needed.
- [ ] `body` is **not** Searchable, and neither is any field other than `title`: Search-before-submit
      uses `self CONTAINS`, which searches *every* searchable field: marking another one searchable
      silently widens it, and since CloudKit returns matches unordered with no relevance scoring, a
      wider match set just makes which five results you get arbitrary.

---

## 7. Privacy

Written so you can lift it into your own privacy policy.

**Who controls the data.** You do. Everything lives in your own CloudKit container, under your own
Apple Developer account. **The author of this package receives nothing** and has no access to any
integrator's data.

**What is collected.** Request title and body; up to three optional images; device model; OS version; app
version and build; platform; any metadata your app attaches through `FeedbackPrefill`; and the
CloudKit user record ID.

**What is public.** Every field on a `Request`. **including device model, OS version and app
version**. Is readable by any user of your app. This is normal for a public issue tracker and those
values are not sensitive, but say so rather than implying otherwise. Only `RequestMetadata` is
restricted to you and the person who submitted it.

**Pseudonymous, not anonymous.** CloudKit stamps a readable `creatorUserRecordID` on every record.
One person's requests, votes, replies and reports are therefore correlatable by anyone who queries
the container. There is no name and no email attached, but this is not anonymity, and it should not
be described as such.

**Reports are not confidential.** Report records are world-readable, because every client counts them
locally to apply the auto-hide threshold without waiting for you to act. A consequence is that the
reporter is discoverable via that same `creatorUserRecordID`. If you would rather have reporter
anonymity than auto-hiding, drop `GRANT READ TO "_world"` from the `Report` record type: hiding then
only happens when you act on a report.

**Follows are private.** Which requests you follow is readable only by you and the developer, not by
other users. It is the one signal here that is not public.

**Activity is world-readable** for a structural reason: the recipient is not the record's creator (you
are), so `_creator` does not grant them access. Activity messages only ever concern publicly visible
requests.

**One report per person per request.** Report records are named `report_<request>_<user>`, so a second
report from the same person collides server-side and is ignored. Nobody can push a request over the
auto-hide threshold on their own. Votes work the same way.

**No account required, and none is created.** No email, no sign-up, no password. Users only need to
be signed in to iCloud. And even that is only needed to write. Browsing works signed out.

**Honouring a deletion request.** Users can delete their own content from **My data**. You can do the
same from the portal, keyed by `creatorID`, so a request that arrives by email can be actioned.
Deletion is real and it cascades: deleting a request takes the votes and replies other people left on
it with it. Both confirmation dialogs say so before you commit.

Requests, replies and reports (everything the user wrote) are deleted. **Votes cast on other
people's requests are deliberately left in place:** a vote is a bare reference with no content of its
own, and deleting them would silently rewrite other people's totals. Users can withdraw any
individual vote from the request itself, and the confirmation dialog says which is which.

**No tracking, no analytics, no third-party sharing, no ads.** `PrivacyInfo.xcprivacy` ships inside
the package and Xcode folds it into your app's privacy report. It does **not** relieve you of your
own App Store Connect privacy answers.

---

## 8. Upgrading from 1.x

**Breaking, with no data migration.**

- **Your existing GitHub issues are not imported.** Export them yourself first if you want them.
- The entire v1 GitHub API surface is gone: `GitHubService`, `GitHubCredentials`, `GitHubIssue`,
  `VotingService`, `IssueOwnershipService`, `IssuesListView`, `CompletedIssuesView`.
- `DeviceInfo.generateReport()` now returns a structured `DeviceEnvironment` via
  `DeviceInfo.current()` instead of a formatted string. `getDeviceID()` and `getIOSVersion()` are
  deleted. The former minted a persistent tracking UUID that nothing needed.
- Local vote and ownership tracking in `UserDefaults` is gone entirely. The server is the source of
  truth, so a reinstall no longer hands someone a second vote.
- Votes can now be withdrawn, requests can be followed without voting, reports carry a category, a
  request can hold up to three images, and completed requests record the version that fixed them. All
  five need the schema re-imported.
- **Revoke your GitHub personal access token.** It is compiled into every 1.x build you have already
  shipped, and removing the code here does not remove it from those.
- SPM users pinned to `from: "1.x"` will not be pulled across automatically. **Tag your final 1.x
  release before merging** so anyone pinned to it keeps working.

---

## License

MIT. See [LICENSE](LICENSE).
