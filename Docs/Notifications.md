# Notifications

The package uses CloudKit query subscriptions for activity updates and new requests. It does not run
a notification server.

## Host-app localization keys

CloudKit delivers localization keys, and the device resolves them against the host app:

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

`ACTIVITY_TITLE` is the only formatted value. CloudKit substitutes the triggering record's request
title for `%@`. Body strings take no localization arguments.

If a notification displays a raw key, add the missing key to the host app's string catalog and
rebuild. Values are resolved on-device, so changing translated wording does not require replacing the
subscription.

## Permission and registration

The system permission prompt appears after the user's first successful request submission. Opening
the board does not prompt.

Once permission exists, the app registers with APNs on every launch. CloudKit subscriptions use
deterministic IDs and are safely attempted again during startup.

Required app capabilities:

- iCloud with the configured CloudKit container
- Push Notifications

## What is delivered

Activity subscriptions fire when a developer changes status, replies, marks a request complete,
moderates an image or announces a shipped version. A separate developer subscription fires for a new
request created by someone else.

The notification title is the request title. The body is a short localized action such as “New
reply.” The activity feed carries the full display-ready message.
