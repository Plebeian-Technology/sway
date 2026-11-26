---
lat:
  mode: explanation
---

# Org-notification cascade and defaults

Organization notification preferences support account-wide default settings alongside per-organization overrides across web and mobile clients.

Account preferences govern event subscriptions and delivery cadences, coordinating cascading updates across followed organizations when default rules change.

## Where organization notification copy is shared across pickers and settings

`PARITY_COPY.orgNotifications` centralizes preference phrasing across single-organization modals and account-level notification preference panels.

Individual organization preference pickers and account-wide default panels share identical event types and cadence options. [[app/frontend/sway_constants/parityCopy.ts#PARITY_COPY]] supplies unified labels for position events and delivery frequencies across web and mobile surfaces.

## Why the skipped-picker test separates user defaults from column defaults

Distinct user and column defaults prove `OrganizationFollow.seed_attrs_from` copied the skipped preference.

The browser example sets the two sources to different values. If they matched, the assertions would pass even when the copy step was skipped.

## Notification records are destroyed through user associations

The digest queue and delivery ledger use `dependent: :destroy` because their `user_id` columns have indexes but no foreign keys.

The database cannot cascade these rows when a user is deleted. The associations on [[app/models/user.rb#User]] therefore own cleanup for [[app/models/pending_organization_digest_entry.rb#PendingOrganizationDigestEntry]] and [[app/models/organization_notification_delivery.rb#OrganizationNotificationDelivery]].

## Only supported follow preferences can be cascaded

The user-default update passes a follow-column name to [[app/models/user.rb#User#cascade_org_pref_off!]], so the method accepts only the three notification booleans that have matching user defaults.

The allowlist keeps dynamic bulk updates within the preference mapping in [[app/models/user.rb#User#apply_org_notification_defaults!]]; arbitrary columns must not become mutable through this helper.

## Turning a user default off disables existing follows

When a user changes a notification default from on to off, existing follows are turned off for that preference; turning it back on leaves each follow's explicit choice unchanged.

The one-way cascade respects per-organization overrides. A follow that was individually muted stays muted when the account default is enabled again, while disabling the default immediately suppresses that notification across existing follows.

## User and follow cadence enums keep the same integer mapping

The user default and each follow store matching integer values for `every_change`, `daily`, and `weekly`.

[[app/models/organization_follow.rb#OrganizationFollow#seed_attrs_from]] copies the user's stored enum value directly into a new follow. Changing either mapping alone would silently assign a new follow the wrong cadence.

## Why update creates the preference row on write

Updating notification preferences creates preference rows on demand rather than raising 404 errors for unseeded accounts.

`Api::V1::NotificationPreferencesController#update` creates the `NotificationPreference` row for any allowlisted key rather than returning a 404 error on a missing record. `NotificationPreference.seed_defaults_for` only executes during mobile registration, so accounts created via web registration or before preference keys existed lack pre-seeded rows. A bare `find_by` would return 404 on the mobile master toggle, snapping optimistic UI switches back to off. Because `org_position_taken` gates the organization notification feature, that failure would permanently block user activation. This behavior mirrors the web application's `find_or_create_by!` pattern while unlisted keys still return 404.

## Why the master toggle checks presence, not truthiness

Master notification toggles evaluate parameter presence rather than boolean truthiness to prevent dropping explicit false values.

Evaluating whether `org_position_taken` was provided rather than truthy is necessary because Ruby evaluates `false.present?` as `false`. Mobile clients transmit explicit JSON booleans, causing `if master_val.present?` checks to discard disable requests. Checking `unless master_val.nil?` processes explicit `false` values correctly while skipping omitted keys.

## Why checkbox values are cast to real booleans before persisting

Checkbox form parameters are cast through boolean type helpers before saving to prevent truthy string values from persisting as enabled.

`OrganizationFollowsController#follow_prefs_params` casts checkbox parameters (`notify_on_new_position`, `notify_on_support_change`, `notify_on_summary_change`) through `ActiveModel::Type::Boolean` prior to database writes. Because string `"false"` evaluates as truthy in Ruby, omitting type casting would cause unchecked submissions to save as true. `NotificationPreferencesController` applies the identical casting mechanism to its boolean fields.

## Why only an OFF flip cascades

Disabling notification defaults cascades to disable follows while enabling defaults leaves per-organization overrides intact.

Turning an event default off disables that setting across all followed organizations, whereas enabling a default cascades nothing to preserve existing per-organization choices. State snapshots taken prior to updates allow cascade routines to distinguish an active off transition from settings that were already disabled.

## When OrgPreferencePickerModal opens

The organization preference picker modal opens immediately upon following an organization or via preference action controls.

The modal opens automatically after a user follows an organization so preferences can be configured immediately. Existing follows access the modal through the dedicated "Preferences" button.

## Why OrgPreferencePickerModal's create mode POSTs instead of PATCHing

In create mode, the modal submits POST requests to initialize follow rows and preferences simultaneously when no prior follow record exists.

For members lacking an existing follow record, `createMode` dispatches a POST to `/organization_follows` to initialize the follow row with preferences in a single transaction instead of sending a PATCH to `/organization_follows/:id/preferences`. The backend accepts optional `organization_follow` parameters in `create` actions, applying them after seeding from user defaults. When `createMode` is false, requests dispatch as PATCH updates against existing rows.

## Mobile: NotificationPrefsScreen organization position updates card

The mobile organization position updates card configures event-type switches and notification delivery frequencies.

Below the primary notification switches, `NotificationPrefsScreen` (`mobile/src/screens/NotificationPrefsScreen.tsx`) displays an "Organization position updates" card. It retrieves `GET /api/v1/notification_preferences/org_defaults` on mount, displaying three event switches and a delivery-frequency selector, and persists modifications with `PATCH` requests to the same endpoint. Updates cascade selectively: turning event types off disables notifications across followed organizations, whereas enabling event types does not cascade.

The master organization-position toggle is located among the primary switches above, leaving the card to configure the three event defaults and frequency without duplicate controls.

