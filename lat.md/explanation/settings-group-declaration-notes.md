---
lat:
  mode: explanation
---

# Settings group declaration notes

Notes on `Sway::Settings::Base` (`lib/sway/settings/base.rb`) and the per-group classes that subclass it (`Sway::Settings::DevLogin`, `Ops`, `Upstream`, `Mobile`, `Webauthn`).

## Why every group subclasses Base and declares its own env_prefix

`Base` holds the shared behaviour every settings group needs, but is not instantiated directly.

Every group subclasses it and declares its own `env_prefix` and `config_name` (a structural spec enforces this): inheriting a prefix from a shared base binds the wrong one silently.

## Why the required-attributes check moves to the end

The `anyway_config` gem registers its own required-attribute check as `Base`'s first `load_callback`, so a subclass's `on_load` repair — appended after it — would never get to run before the check raises.

`Base` moves that check to the end of `load_callbacks` so a blank value can fall back to its default before "still nil, and required" is judged. Without this move, a required attribute with a default, given a blank value, raised before the repair ran.

## Why to_rbs renames the generated interface

`Anyway::RBSGenerator#to_rbs` (gem 2.8.1, `lib/anyway/rbs.rb:21-28`) always names the generated interface `_Config` when the class has a namespace.

`Anyway::RBSGenerator#to_rbs` (gem 2.8.1, `lib/anyway/rbs.rb:21-28`) always names the generated interface `_Config` when the class has a namespace — fine for one group, but a second committed `sig/lib/sway/settings/*.rbs` alongside it declares the SAME `module Sway::Settings; interface _Config`, an `RBS::DuplicatedDeclaration` (for example `rate_limits.rbs` beside `upstream.rbs`). `Base.to_rbs` renames to one interface per class so every group's committed signature can coexist in the same namespace; `settings_signatures_spec.rb` compares a committed file against this same overridden method, so the verbatim-regenerate contract still holds.

## Why freeze_mutable_attributes! must run last

A String/Array attribute reader otherwise hands out the same mutable object on every call (`Sway::Settings.webauthn.allowed_origins` would return the identical, unfrozen Array each time).

That array reaches `WebAuthn::RelyingParty.new` and `/.well-known/assetlinks.json`; one caller mutating it would corrupt every other caller's view of a security boundary.

`Base.freeze_mutable_attributes!` is not called automatically. A group with its own `on_load` repair (`Mobile`, `Webauthn`) must call it LAST, after that repair, because a later `on_load` reassigning the attribute (e.g. `self.foo = foo.compact`) hands back a fresh, unfrozen object that undoes an earlier freeze. `Mobile#android_cert_sha256_fingerprints` and `Webauthn#allowed_origins` both compact their array first and freeze second for exactly this reason.

## Why some groups declare env_prefix ""

`DevLogin`, `Ops`, and `Upstream` all declare a blank `env_prefix`, each for the same reason: their attribute names share no common prefix to bind to.

- `DevLogin`: the phone-check-skip switch (read nine times across six
  controllers, migrated in this same plan) shares no prefix with the seven
  stand-in-account values the stand-in account is built from when that
  switch is on (`SkipPhoneVerificationProvisioner`).
- `Ops`: none of its five names (the notifications phone number, the
  BootBackupGuard deploy stamp, the backup-skip switch, the in-container
  flag, and the dev tunnel host) share a common word.
- `Upstream`: none of its seven upstream base-URL names share a common word
  either — each attribute reads its own bare environment variable name in
  upper case, with no lookup table between a call site and the variable it
  names.

## Why the class is named Upstream, not UpstreamConfig

Zeitwerk autoloads `lib/` and expects this file to define `Sway::Settings::Upstream`, matching its path (`config.autoload_lib` in `config/application.rb`).

`Anyway::Config` infers a config name only from a class ending in `"Config"`, so that inference is bypassed here with an explicit `config_name` call instead.

## Why dev_account_full_name (and its siblings) have a real default

`DevLogin`'s seven stand-in-account attributes (`dev_account_full_name`, `dev_account_street`, etc.) default to real Baltimore City Hall values.

A `nil` default here plus the `required` block aborted Rails boot on any checkout without a hand-maintained `.env.development`/ `.env.test` (fresh clone, fork, or a CI job that doesn't set them). A real default means the app boots everywhere.

## Why Mobile.android_cert_sha256_fingerprints gets compacted

The array caster leaves a nil in the list for a genuinely empty entry (two commas in a row) or a whitespace-only value.

The array caster leaves a nil in the list for a genuinely empty entry (two commas in a row) or a whitespace-only value — its own per-element `:string` caster returns nil for blank text, and the gem's own comma split does not drop it. This is the `.reject(&:empty?)` the old read did, moved to run once the array is built via `on_load`.

## Why Ops.sway_deployed_at has no default

`BootBackupGuard`'s own comment records that "cannot tell which deploy this is" leans safe (backs up) rather than guessing, so nil here is the honest answer.

`BootBackupGuard`'s own comment records that "cannot tell which deploy this is" leans safe (backs up) rather than guessing, so nil here is the honest answer — `sway_deployed_at` is absent in development and test rather than given a placeholder default.

`sway_deployed_at` stays text, not a time: an unquoted value here was already coerced into a `Time` in `config/deploy.yml`, which `Time.iso8601` could not re-parse. `SWAY_DEPLOYED_AT` has two doors: `lib/sway/release.rb` reads `ENV` directly, and `config/environments/test.rb` depends on that — deliberate, not an oversight.

## Why settings_signatures_spec.rb exists, and why it is not a Steep check

`bin/steep check` validates that a committed `.rbs` signature is internally CONSISTENT, never that it is CURRENT.

`bin/steep check` validates that a committed `.rbs` signature is internally CONSISTENT, never that it is CURRENT — a committed `sig/lib/sway/settings/<group>.rbs` that no longer matches its class still type-checks cleanly, describing a class that no longer exists, with every call site through it unchecked from that point on. There is no other check of this kind anywhere in the repository (grepped `Rakefile` and every file in `lib/tasks/`).

`spec/lib/sway/settings_signatures_spec.rb` is that check, and it is kept out of Steep on purpose: only a spec can compare a committed file's TEXT against what the class generates right now, by calling `.to_rbs` again and diffing. Its `SettingsSignaturesSpecHelpers` module is declared outside `RSpec.describe`, not as a `def` inside one, because Steep resolves neither shape the same way a `def` inside a `describe` block resolves (see `spec/lib/sway/settings_spec.rb`'s `SettingsSpecHelpers` for the same reasoning, and `sig-test/lib/sway/subprocess_spec.rbs` for the precedent).

The missing-file example fails rather than skips: a skip on a missing file is the same as no check at all for a group somebody forgot to commit a signature for.

## Why the Congress Legislators base URL keeps its trailing slash

`congress_legislators_base_url` in [[lib/sway/settings/upstream.rb#Upstream]] retains its trailing slash in the default declaration.

The Congress legislator seed fetchers resolve relative resource paths and data file names directly against this base URL, so normalizing the trailing slash away would drop the final path segment during resolution.
