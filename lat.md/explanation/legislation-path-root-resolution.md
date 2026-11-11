---
lat:
  mode: explanation
---

# Legislation path root resolution

How Legislation::Paths resolves its root directory across production, development, and isolated test runs, and the history behind the attachments directory layout.

## Where the root comes from

Production sets `LEGISLATION_ROOT=/rails/storage/legislation` (`config/deploy.yml`) so pipeline files land on the SSD volume that survives deploys — the container's non-root `rails` user cannot write to the old default path.

Development and test keep the default inside the repo (`Rails.root.join("legislation")`).

Each stage can also override its own root (`LEGISLATION_BILLS_RAW_ROOT` and similar) so specs cannot reach each other's files; a per-stage override wins over the shared root — the path becomes `<root>/<relative>` otherwise, so setting `legislation_root` alone moves every stage at once. A relative override resolves against `Rails.root`; an absolute one is used as-is — this is what `Legislation::Paths.resolve` does, and it's how per-stage settings have always behaved and what the specs count on.

A stage value set to an empty string behaves as unset, not as an override to an empty path: `Sway::Settings::Base`'s `:string` caster already turns a blank env value into `nil`, and `Legislation::Paths.sub`'s `.to_s` call turns that `nil` back into `""`, so it falls back to `root` — never to `Rails.root` directly.

Every path is computed fresh on each call, never memoized, so a spec that stubs `Rails.root` or changes a setting between examples sees the change immediately.

A change (`LEGISLATION_ATTACHMENTS_ROOT`) once landed without updating this module's own docstring, which at the time spelled out every per-stage override by name — the sixth was silently missing from that list for a while. The docstring no longer enumerates the overrides by name (it says "and similar" instead), so that specific failure mode is gone, but the underlying lesson holds: when this file gains a new per-stage `sub(...)` call, check whatever prose nearby claims to be exhaustive.

## Test isolation

`Legislation::Paths.root` also checks `Sway::LegislationTestIsolation.root_override` before falling back to the repo default.

That module places an isolated rspec run's files on tmpfs instead of the bind-mounted source tree every container from the same checkout shares — two concurrent runs both defaulting to the repo path once collided there, deleting each other's pipeline fixtures mid-run. Neither of that module's two variables is set outside an isolated rspec invocation, so the default is unchanged everywhere else.

That isolation logic lives in `lib/sway/legislation_test_isolation.rb`, not in `Legislation::Paths` itself, because `lib/` is the one directory the app-wide `ENV` guard (`sway:lint:env_reads`) does not cover. Reconciling these two harness-owned reads against that guard was the open question, and this extraction is the resolution the guard's single-allowed-path property depends on.

## The attachments directory's rename history

`Legislation::Paths.attachments` used to be one flat directory keyed on the bare Legistar attachment id, which assumed a single jurisdiction.

A second city was planned (`AttachmentUrl`'s allowed hosts were widened to `*.legistar1.com`), so both keys now carry the jurisdiction: the path gets the `SwayLocale` name, and `testimony_attachment_classifications` indexes on `(sway_locale_id, attachment_id)` together — re-keyed in one change.

Leftover files from two earlier naming schemes can still sit in this directory on any developer machine that ran an old version. Nothing lists the directory — every reader builds one exact path from a DB record — so those files are dead weight, not a correctness problem.

This was decided twice: leave the old files in place rather than write a migration to remove them. Production has none of the old files. A file-rename migration cannot join the database transaction and can die mid-run. The actual fix, when needed, is one command: delete the directory. That's safe because the directory is a cache, not the source of truth — testimony is assembled from these files, so clearing it only means attachments that no longer download stop contributing until they download again.

## Why artifact_presence_spec.rb points Rails.root at a temp directory explicitly

`Pipeline::ArtifactPresence`'s spec points `Rails.root` at a temp directory to isolate its filesystem assertions.

It also points `legislation_root` at the same temp directory rather than relying on `Rails.root` stubbing alone: `Legislation::Paths.root` checks `legislation_root` before it checks `Rails.root` (a later change gave it an isolation branch in between, for concurrent test runs), so stubbing `Rails.root` alone no longer moves it under an isolated run. The spec says explicitly where the code should read from, the same way production does with this same setting.

`with_app_config` wraps `example.run`, not just the before/after pair: RSpec's mock framework is not yet set up at the point an `around` hook's own code runs before calling `example.run`, so the `Rails.root` stub has to stay in a plain `before` hook (which runs inside `example.run`) rather than moving up into the `around` block alongside it.

### Why the spec forces several model classes to load before faking Rails.root

Some model classes read the real `config/storage.yml` the first time they load: `Legislator` declares `has_one_attached :photo`, which loads `ActiveStorage::Blob`, which reads `Rails.root.join("config/storage.yml")`.

If that first load happened after the fake root was in place, `ActiveStorage` would not find its config. The spec's `before(:all)` hook names `Bill`, `Legislator`, `LawSection`, `BillSectionReference`, and `BillLlmProvisioning` explicitly (`.each(&:name)`) so they finish loading while `Rails.root` is still the real one.
