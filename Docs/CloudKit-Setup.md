# CloudKit setup and environments

This guide expands the six-step setup in the README. Complete the README first, then use this page
for verification or environment changes.

## Importing the schema

CloudKit schema commands require a management token. Create one in CloudKit Console under
**Settings → Tokens & Keys → Management Tokens**:

```sh
xcrun cktool save-token --type management
xcrun cktool get-teams
```

Choose the schema that matches your configuration:

- `Schema.ckdb` with `allowComments: true`
- `Schema-NoComments.ckdb` with `allowComments: false`

```sh
xcrun cktool validate-schema --team-id <TEAM> --container-id <CONTAINER> \
  --environment development --file Schema.ckdb

xcrun cktool import-schema --team-id <TEAM> --container-id <CONTAINER> \
  --environment development --file Schema.ckdb
```

Importing is supported only in Development. Verify what CloudKit stored without overwriting the
checked-in schema:

```sh
xcrun cktool export-schema --team-id <TEAM> --container-id <CONTAINER> \
  --environment development --output-file ExportedSchema.ckdb
```

The exported format contains no explanatory comments. Keep documentation outside schema files.

## Developer access

The developer portal has two independent gates:

1. `developerUserRecordIDs` makes the portal visible.
2. Membership in the CloudKit `dev` role authorizes its writes.

Run the app at least once for each developer Apple Account so CloudKit creates its built-in user
record. Find the record in the public database's `Users` type and add `dev` to its roles.

Development and Production have separate user records and role memberships. Repeat the assignment
after deploying the schema.

## Development and Production

An Xcode development build normally uses CloudKit Development. App Store and TestFlight builds use
Production. To inspect real feedback from a debug build, set the app entitlement explicitly:

```xml
<key>com.apple.developer.icloud-container-environment</key>
<string>Production</string>
```

Entitlements are applied when the app is signed. Rebuild and reinstall after changing the value.
Leave `aps-environment` under Xcode's control; APNs and CloudKit environment entitlements serve
different purposes.

Use Development for schema changes, disposable feedback and destructive moderation tests. Use
Production for real user data. Production fields and record types can be added but cannot be removed,
renamed or retyped, so validate changes in Development first.

## Release flow

`Update Pending` and `Complete` distinguish a finished fix from an available release:

- **Update Pending:** the change is written but users cannot install it yet.
- **Complete:** the release is available. The portal records the version that contains the fix.

`RoadmapView` groups completed requests by their resolved version. Version sorting is numeric, so
`2.10` sorts after `2.9`.

## Production checklist

- [ ] The schema is deployed to Production.
- [ ] Developer user records have the `dev` role in Production.
- [ ] The release build uses the intended CloudKit container and Production environment.
- [ ] A Production request can be created and read.
- [ ] Voting, following and reporting work.
- [ ] A developer can change status and reply.
- [ ] Notification permission can be granted and a push is delivered.
- [ ] Delete-my-data succeeds.

See [Schema and permissions](Schema-and-Permissions.md) for the index and grant checklist.
