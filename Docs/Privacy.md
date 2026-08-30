# Privacy guidance

This is implementation guidance, not legal advice. Adapt it to the host app's privacy policy and App
Store Connect disclosures.

## Who controls the data

All records live in the integrator's CloudKit container under its Apple Developer account. The
package author receives no data and cannot access the container.

## Data collected

- Request title and body
- Up to three optional images
- Device model, OS version, app version, build and platform
- Optional metadata supplied through `FeedbackPrefill`
- CloudKit user record ID
- Votes, follows, replies and report categories

## Visibility

Every `Request` field is public to users of the app, including its device and app-version fields.
`RequestMetadata` is readable only by the creator and developer role.

CloudKit record creator IDs are pseudonymous, not anonymous. Requests, votes, replies and reports can
be correlated through that ID even though the package collects no name or email.

`Report` records are world-readable so every client can count reports toward the auto-hide threshold.
They therefore contain only a category, never private-feeling free text. `Follow` records are
readable only by their creator and the developer role.

`Activity` is world-readable because its recipient is not its creator. Activity messages concern
public requests and contain no private metadata.

## Deletion

Users can delete their posted requests, replies and reports from `MyDataView`; their private follows
are removed as well. Deleting a request cascades to replies and votes attached to that request.

Votes the user cast on other people's requests remain because they contain no prose and removing them
would rewrite other people's totals. A user can withdraw an individual vote from its request.

Developers can perform the same deletion by creator ID when handling an external deletion request.

## Manifest

`PrivacyInfo.xcprivacy` declares user content, optional photos, diagnostic context, user ID and the
same-app UserDefaults access used for activity and local blocking. The package performs no tracking,
analytics, advertising or third-party sharing.

The manifest does not replace the host app's own privacy manifest, privacy policy or App Store Connect
answers.
