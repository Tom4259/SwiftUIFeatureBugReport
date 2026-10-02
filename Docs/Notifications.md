# Notifications

The package uses CloudKit query subscriptions for activity updates and new requests. It does not run
a notification server.

## Notification text

CloudKit delivers localization keys, and the device resolves them against the host app. Every key the
package sends **is its own en-GB source string**, the same convention the rest of the package uses:

```text
"Status updated"
"New reply"
"Marked complete"
"Your image was approved"
"Your image was removed"
"Shipped"
"New request"
"A user created a new request."
"New comment"
"A user commented on a request."
"%@"
```

**Nothing here has to be added to the host app.** A push key with no entry in the app's catalog is
displayed verbatim, so an app that adds none of these shows the English above. Earlier versions sent
tokens such as `ACTIVITY_COMMENT`, which is what arrived on the lock screen in that case.

`%@` is the activity title: CloudKit substitutes the triggering record's request title for it. There is
no English in that line to translate, because the one value it carries is a title the user typed.
Bodies take no arguments.

## Translating them

Add the strings above to the host app's `Localizable.xcstrings` or `Localizable.strings` as keys, and
translate them there. Keys resolve on-device, so adding a language or rewording a translation needs
nothing from the subscription.

To put something around the request title, give `%@` an entry — `"%@" = "Update: %@";`.

Rewording the **English** in the package is different: the English *is* the key, so the subscription
starts pushing a different one and has to be saved again before any device sees it. See below.

## Permission and registration

The system permission prompt appears after the user's first successful request submission. Opening
the board does not prompt.

A developer is asked when they first open the developer portal instead. They never submit a request,
so the first-submission prompt would never reach them and both developer subscriptions would end up
delivering to a device that had never registered with APNs. The portal is the one screen those two
pushes exist to send them back to, which makes opening it the developer's equivalent intent signal. A
developer who has already answered is not asked again.

Once permission exists, the app registers with APNs on every launch. CloudKit subscriptions use
deterministic IDs and are safely attempted again during startup.

A subscription's text is fixed **when the subscription is saved**, not per event, so changing any of the
keys above only reaches devices once the subscription is saved again. Saving over an existing ID
replaces it, which the next launch does. If old wording keeps arriving, delete the subscription in
CloudKit Console and relaunch — `ActivityService` swallows save errors by design, since a subscription
that already exists is the expected outcome rather than a failure.

Required app capabilities:

- iCloud with the configured CloudKit container
- Push Notifications

## What is delivered

Activity subscriptions fire when a developer changes status, replies, marks a request complete,
moderates an image or announces a shipped version. Two separate developer subscriptions fire for a
new request and for a new comment, in both cases only when someone else created it.

For an activity notification the title is the request title and the body is a short action such as “New
reply.” The activity feed carries the full display-ready message.

The developer's new-request notification reads “New request” over “A user created a new request.” The
new-comment notification reads “New comment” over “A user commented on a request.” Neither pushes the
request's own title: one subscription means one fixed format string, and the portal queue is a tap
away.

The developer's two notifications write no `Activity` record, so they do not appear in the Updates
feed. The portal queue is the developer's durable view and the push is only the nudge to open it. A
developer reply, by contrast, does write one, so the user sees it in Updates even if the push was
missed or notification permission was refused.
