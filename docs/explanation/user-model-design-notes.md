---
mode: explanation
summary: "Design notes for User: the ADMIN_PHONES/API_USER_PHONES credential split, the email blocklist boot-fallback, why two has_many associations cascade despite no database FK, the cascade_org_pref_off! allowlist, revoke_all_devices!, the failed-to-completed registration transition, and the as_json security wrapper."
status: agent-extracted
related: [docs/explanation/organization-follow-notification-design.md, docs/explanation/api-key-hmac-secret-handling.md, docs/explanation/sway-locale-model-design.md]
---
<!-- vale Vale.Spelling = NO -->

# User model design notes

## Why ADMIN_PHONES and API_USER_PHONES are read differently in production

Both `ADMIN_PHONES` and `API_USER_PHONES` are built by
`phone_list_from_credential`, which reads through `EnvSecret` so a `kamal
env push` trailing newline is stripped before the phone list is split —
not because either digit string is otherwise damaged by a newline.

Both `ADMIN_PHONES` and `API_USER_PHONES` are on `config/deploy.yml`'s secret
list, so production receives them.

## Why the email blocklist falls back to a hardcoded set at boot

`EmailValidator#in_blocklist?` caches the disposable-email blocklist under
`Rails.cache`, reading it from a file downloaded at boot
(`SwayTask.download_email_blocklist`). If that file is absent — the
download hasn't run yet, failed, or this is a fresh boot before the task
fires — the check falls back to a small hardcoded set
(`simplelogin.com`, `mozmail.com`, `privaterelay.appleid.com`) rather than
raising `Errno::ENOENT` on every single email verification in the
meantime.

## Why pending_org_digest_entries and org_notification_deliveries cascade despite no FK

`User has_many :pending_org_digest_entries, dependent: :destroy` and the
matching association for `:org_notification_deliveries` exist even though
neither child table carries a database foreign key back to `users` — both
are kept in the database (rather than in memory) specifically so a
production restart cannot lose a pending notification or a sent-marker.
Without Rails-level `dependent: :destroy`, a deleted user's rows (from
`OnDeactivatedPhoneDeleteUserJob`, for example) would sit in either table
forever, since no database-level `ON DELETE CASCADE` exists to clean them
up. Destroying the `User` record is what actually clears them.

## Why cascade_org_pref_off! allowlists its target column

`CASCADABLE_FOLLOW_COLUMNS` is the only set of columns
`#cascade_org_pref_off!` may bulk-update via `update_all`. Without this
allowlist, a caller could pass any column name at all straight through to
raw SQL. The method converts a `String` argument to a `Symbol` BEFORE
checking it against the allowlist — a column name arriving as a `String`
(straight out of request params, for instance) would otherwise fail a
`Symbol`-keyed allowlist check even when it names a legitimate column;
`to_sym` changes the type, not what the gate actually allows through, so
junk input still fails it.

`update_all` sends raw SQL and does not stamp `updated_at` on its own the
way a normal ActiveRecord write would, so the method passes
`updated_at: Time.current` explicitly — otherwise every cascaded row would
keep a timestamp from before the change that actually touched it.

Turning one kind of notification OFF for everything turns it off on every
organization the user already follows. Turning it back ON deliberately
does NOT spread the same way — callers only ever reach this method with
`false`, so there is no corresponding "cascade on" behavior to reason
about.

## Why revoke_all_devices! wraps its loop in one transaction

`#revoke_all_devices!` revokes every active device for a user — and, via
`UserDevice#revoke!`, cascades to each device's `api_keys` — inside a
single transaction, used by both "sign out all devices" and user-deletion
flows. Wrapping the whole loop in one transaction means a failure partway
through leaves no device revoked at all, rather than leaving the user
signed out of some devices and still signed in on others.

## Why registration_status can jump from failed straight to completed

The `registration_status` state machine's `complete` event allows
`transition failed: :completed`, in addition to the ordinary `pending` and
`processing` sources. Having `UserLegislators` is what "finished
registering" actually means for this app, so a user whose BACKGROUND
registration job failed after those records were already created can
still put their own registration right: `authenticate_sway_user!` calls
`complete!` on their very next request. Without this transition,
`complete!` raised `StateMachines::InvalidTransition` during sign-in, and
every such request came back a 500 instead of quietly finishing the
registration that had, in fact, already succeeded at the database level.

## Why as_json delegates to to_builder instead of the default

`User#as_json` is overridden to call `to_sway_json` (built from
`#to_builder`'s short, explicit field list) rather than falling through to
ActiveRecord's default `as_json`, which would dump every column —
including login IP addresses, `webauthn_id`, and `sign_in_count`. Routing
through `to_builder` means a stray `render json: user`, or a `User`
instance tucked inside some other payload, can only ever emit the fields
that have actually been checked and intended for exposure.
`to_builder`/`to_sway_json` still adds the computed `is_admin` key
(`is_sway_admin?`) for an admin, on top of the raw columns it selects.

## Why to_builder sends theme_mode

`theme_mode` goes out in `to_builder` specifically because the mobile
app's `ThemeProvider` reads it at startup, so a returning user's saved
Auto/Light/Dark choice is restored instead of the provider falling back to
the device's own OS-level setting. The column itself predates the mobile
switch that reads it; the web app ignores this field entirely, and no
other serializer needed to change when it was added.

## Why `is_admin` is never mass-assigned from session-carried attributes

`Users::Webauthn::RegistrationController#sanitized_user_attributes` builds
the attribute hash passed to `User#assign_attributes` during passkey
registration, and it deliberately leaves `is_admin` out. `is_admin` is a
privilege flag and must be DERIVED, never mass-assigned here — the
`#is_admin` *method* already checks the `ADMIN_PHONES` allowlist. On a
NEW user, `User`'s `before_create` reset would hide a stray mass-assigned
value, but on an EXISTING user (the update path this same method serves)
it would stick, silently granting admin from session data an attacker
could have tampered with.

## Why the test suite snapshots and restores ADMIN_PHONES/API_USER_PHONES unconditionally

`User::ADMIN_PHONES` and `User::API_USER_PHONES` are frozen at class-load
time, so granting one example's user admin/API status means `remove_const`
+ `const_set` to a throwaway value — there is no setter. Two call sites do
this (`shared_context "Setup"` in `spec/support/setup.rb`, and the
`:sway_admin` factory trait used directly by 20+ spec files) and neither
restored the original value; every other site in the suite that mutates
`ADMIN_PHONES` does restore it in its own after/ensure block, which is what
made these two the outliers rather than the norm.

Across worker PROCESSES this was harmless (each `parallel_tests` worker has
its own Ruby), but WITHIN one worker, sharding is the first time this suite
has ever run one example right after another that leaves this mutated — a
later example reading `ADMIN_PHONES`/`API_USER_PHONES` would see whichever
example mutated it last, not the pristine ENV-derived value (an
order-dependence hazard). `spec/rails_helper.rb`
snapshots the pristine value once per example and restores it
unconditionally in `ensure`, regardless of which mechanism (or none) did the
mutating, so a leak here is no longer possible from any call site, present
or future.

## Why create_user_invite_url is tied to creation, not a plain after_commit

`create_user_invite_url` must fire exactly once, at the row's creation, and
never again on later updates. A plain `after_commit` would fire on every
commit, and users really do get deleted and recreated in production
(`OnDeactivatedPhoneDeleteUserJob`), so the callback is tied to creation as
a deliberate rule — not something that happens to work only because the
method itself returns early on a non-new record.
