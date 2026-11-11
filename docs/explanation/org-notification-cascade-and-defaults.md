---
mode: explanation
summary: "Why the org-notification defaults endpoints (web NotificationsController and mobile Api::V1::NotificationPreferencesController) create-on-write, check presence not truthiness, and cascade only on an OFF flip."
status: agent-extracted
related: []
---

<!-- vale Vale.Spelling = NO -->

# Org-notification defaults: create-on-write, presence checks, and the asymmetric cascade

Both `NotificationsController#update_org_defaults` (web) and
`Api::V1::NotificationPreferencesController#update_org_defaults` (mobile)
apply the exact same rules to a user's account-wide organization
notification settings, so this doc covers both.

## Why `#update` creates the preference row on write

`Api::V1::NotificationPreferencesController#update` creates the
`NotificationPreference` row for any allowlisted key rather than 404ing on
a missing one. `NotificationPreference.seed_defaults_for` only runs at
mobile registration, so accounts registered on the web — or created before
these keys existed — have none. A bare `find_by` would 404 on the mobile
master toggle, snapping the optimistic UI switch back OFF, and since
`org_position_taken` gates the whole org-notification feature, that would
leave the user unable to ever enable it. This mirrors the web's
`find_or_create_by!` path. An unknown key still 404s.

## Why the master toggle checks presence, not truthiness

Checking whether `org_position_taken` (or its mobile equivalent) was SENT,
rather than whether its value is truthy, matters because Ruby's
`false.present?` is `false`. Mobile clients send a JSON boolean, so an
earlier `if master_val.present?` check silently dropped every "turn OFF"
request. `unless master_val.nil?` handles an explicit `false` while still
skipping an absent key.

## Why checkbox values are cast to real booleans before persisting

`OrganizationFollowsController#follow_prefs_params` casts its three
checkbox fields (`notify_on_new_position`, `notify_on_support_change`,
`notify_on_summary_change`) through `ActiveModel::Type::Boolean` before
persisting. The string `"false"` is truthy in Ruby, so without this cast an
"off" checkbox submission would be stored as "on".
`NotificationPreferencesController` does the same thing for its own
boolean fields.

## Why only an OFF flip cascades

Turning an event-type default OFF also turns that setting off on every
followed organization; turning a default back ON cascades nothing, leaving
each organization's own per-org choice alone. The values are snapshotted
before the update specifically so the cascade can tell an OFF transition
from a value that was already OFF.

## When `OrgPreferencePickerModal` opens

The modal opens immediately after following an organization (follow first,
then let the user adjust preferences right after) and also via the
"Preferences" button on an existing follow.

## Why `OrgPreferencePickerModal`'s create mode POSTs instead of PATCHing

For a member with no follow row yet, `createMode` sends a POST to
`/organization_follows` to create the follow row with preferences in one
step, instead of a PATCH to `/organization_follows/:id/preferences`. The
backend accepts optional `organization_follow` params in the `create`
action and applies them after seeding from the user's defaults. When
`createMode` is false (the default), it sends a PATCH to update the
existing row instead.

## Where the frontend copy for these settings is shared

`PARITY_COPY.orgNotifications` is used by the picker for one organization
(web `OrgPreferencePickerModal`, mobile `OrgPreferenceSheet`) and by the
panel of defaults that apply to all of them (web
`OrganizationsNotificationsPanel`, mobile `NotificationPrefsScreen`).

## Mobile: `NotificationPrefsScreen`'s "Organization position updates" card

Below the four notification switches, `NotificationPrefsScreen`
(`mobile/src/screens/NotificationPrefsScreen.tsx`) shows an "Organization
position updates" card. It fetches `GET
/api/v1/notification_preferences/org_defaults` when the screen opens, shows
three event-type switches and a delivery-frequency picker, and saves with
`PATCH` to the same path. The server applies changes unevenly on purpose:
turning an event type OFF turns it off for every organization the user
follows, while turning it ON does not.

`[platform]`: the master "organization took a position" switch is already
one of the four switches above, so this card shows only the three defaults
and the frequency, and no control appears twice. The master
`org_position_taken` switch lives in the four switches above; this card
shows only the per-organization defaults.
