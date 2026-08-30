# Troubleshooting

## The app crashes when creating the store

Confirm that `FeedbackConfiguration.containerIdentifier` is present in the app target's iCloud
entitlement. `CKContainer(identifier:)` traps when the container is not entitled, before package
error handling can run.

## “CloudKit developer role not configured”

The current user ID is present in `developerUserRecordIDs`, so the portal is visible, but its
CloudKit `Users` record is not a member of `dev` in the current environment. Development and
Production membership are separate.

## The board is empty in a debug build

Check which CloudKit environment the signed app uses. Development and Production have different
records, and deploying a schema does not move test data.

## Production reports an unknown record type or field

Deploy schema changes from CloudKit Console. Importing into Development does not automatically update
Production.

## A notification displays `ACTIVITY_TITLE` or `NEW_REQUEST`

The key is missing from the host app's `Localizable.xcstrings` or `Localizable.strings`. Add all
keys listed in [Notifications](Notifications.md), rebuild and reinstall.

## No notifications arrive

Check all of the following:

- Push Notifications capability is present.
- Notification permission is enabled in system settings.
- The app has launched since permission was granted, allowing APNs registration.
- The CloudKit subscription exists in the same environment as the triggering record.
- The expected localization keys exist in the host app.

## User comments are disabled but CloudKit reports a missing type

Use `Schema-NoComments.ckdb` together with `allowComments: false`. Do not combine the no-comments
schema with `allowComments: true`.

## Schema validation reports an undefined role

The schema must contain `CREATE ROLE dev;` before permissions grant access to `dev`. Both
checked-in schema variants already include it.
