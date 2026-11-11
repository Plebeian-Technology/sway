---
lat:
  mode: explanation
---

# Test-design rationale for settings_spec.rb

This file exercises every registered `Sway::Settings` group class through the same set of generic checks (the "traps" below), rather than one bespoke check per group.

The generic checks work by deriving what to test FROM each class's own declaration — the `SettingsSpecHelpers` methods below make that possible.

## Why EXPECTED_PREFIXES exists

`SettingsSpecHelpers::EXPECTED_PREFIXES` is what the agreed prefix table names, per group.

A group whose names share one prefix declares it (`rate_limits` → `RATE_LIMIT`, `webauthn` → `WEBAUTHN`); a group whose names share nothing reads each bare name (`env_prefix ""`). Only `upstream` was registered when this table was written — a later plan's group with no entry here raises rather than skipping silently, so a new group cannot land without a decision recorded for it.

## Why attributes_without_declared_type exists

`SettingsSpecHelpers.attributes_without_declared_type` returns every declared attribute with no `coerce_types` entry.

`SettingsSpecHelpers.attributes_without_declared_type` returns every declared attribute with no `coerce_types` entry — the only ones the gem's fallback caster still touches (measured against `Anyway::TypeCaster#coerce`: a key present in `coercion_mapping` never reaches the fallback). It returns empty for every real group; a non-empty result is what a broken class looks like.

## Why companion_env_for exists

A required attribute with no default refuses to build rather than repairing a blank value.

Building `klass.new` to test any ONE such attribute — or any other required attribute of the same class — raises before the assertion under test even runs, unless every OTHER no-default-required attribute is also given a value. `companion_env_for` fills exactly those companions, skipping the attribute under test itself, so trap two and trap three (below) can probe one attribute at a time without the class's own required check getting in the way first.

## The three anyway_config traps

Three deliberately-broken probe classes (`NoTypeProbe`.

Three deliberately-broken probe classes (`NoTypeProbe`, `WrongPrefixProbe`, `MissingRequiredProbe`, plus `IntegerProbe` and `FloatProbe` for the unreadable-text checks) each prove one measured hazard can fail the same check a real group passes. None of the five live in `lib/`, so a broken shape never reaches the application. See [[docs/explanation/steep-typed-spec-helpers.md|Why spec helpers avoid `let`, `Class.new`, and `Struct.new` blocks]] for why they are named top-level classes rather than `Class.new` blocks.

**Trap one (automatic casting).** The first measured hazard: the gem casts by default, and the cast damages text (`spike-anyway-config/output.txt` lines 29-36). `NoTypeProbe` is what makes "the same check the broken class fails" half of the trap-one example true, since every real attribute today declares `coerce_types` and so never reaches the fallback caster this trap is about.

**Trap two (blank counts as absent)** and **trap three (binding to the right environment name)** reuse the same probe classes and the `companion_env_for` helper described above to isolate one attribute at a time.

`FloatProbe` exists as a class distinct from `IntegerProbe` because of a code-review finding: bare `Integer()`/`Float()` honor Ruby's literal prefixes (a leading zero reads as octal, `"0x"` as hex — see [[docs/explanation/settings-type-caster-design.md|Why Sway::Settings::Base replaces Anyway::Config's casters]]). These two probes exercise the decimal-only casters directly, since `DevLogin`'s coordinates are the only registered `:float` attributes and neither is written with a leading zero or an `"0x"` prefix in any fixture.

## Why "the enumeration" is a check, not a note

`SettingsSpecHelpers::DECLARED_NAMES` lists every environment name a settings group declares.

The "derived versus declared" example (`Sway::Settings::GROUPS.each_value.flat_map { ... }` compared against `DECLARED_NAMES`) is what makes that list a check rather than a comment — it fails the moment a group's attribute list and the frozen list disagree, in either direction, so every later group's plan has to add its names here too.

## Why LEGISLATION_ROOT and LLM_PROVIDER are pinned against config/deploy.yml directly

54 of the 58 declared names are set nowhere in `config/deploy.yml`, so the DEFAULT written in each declaration is what production actually runs — a tidy-up of either default is a change to production, not a no-op.

The two names production DOES set (`LEGISLATION_ROOT`, `LLM_PROVIDER`) are read out of the deploy file through `SettingsSpecHelpers.deploy_clear_env` rather than typed a second time in the spec: a value typed twice drifts, and the whole point of the example is that the two agree.

The companion example ("declares a default that differs from what the deploy file sets, for both names") is a mutation test in prose form: deleting either line from `config/deploy.yml` raises `KeyError` here (`fetch`, not `[]`), never a silent `nil` — and each declared default differs from what the deploy file actually sets, so changing a default is provably a change to what the Pi runs, not a harmless tidy-up. Run by hand while writing this spec: deleting the `LLM_PROVIDER` line made the example raise `KeyError`; restoring it made it pass again.

## Why the LLM group's boot-path example duplicates a generic one

`Sway::Settings::Llm`'s "raises through `Sway::Settings.build!`" example looks redundant with the generic "unreadable text" trap, which already proves an unreadable whole number raises.

The generic example builds a probe class directly; the LLM-specific one goes through the real boot path, `Sway::Settings.build!`, so the truth "a cap given text that is not a whole number stops the boot" is pinned at the place that actually stops the boot, not only at the class it stops on.

## Why the settings-setter-write guard walks Prism instead of matching text

`spec/lib/sway/settings_spec.rb`'s "no settings-setter call outside lib/sway/settings/" example guards a property the settings move lost.

`spec/lib/sway/settings_spec.rb`'s "no settings-setter call outside lib/sway/settings/" example guards a property the settings move lost: a config object accepts a write even after freeze, and the generated signature declares a setter for every attribute, so a write at a call site type-checks and runs — this spec is the only thing standing between a call site and a silent write.

A written setter is a syntax SHAPE: a call whose receiver chain starts at `Sway::Settings` and whose method name ends in an equals sign. A comment or a string literal holding the same words is not that shape — the exact distinction a regexp cannot make and a syntax tree can, by construction. `SettingsSetterVisitor` walks Prism's parse tree instead: `attribute_write?` already excludes comparison operators (`==`, `<=`, ...), since Prism only sets that flag for genuine `receiver.name = value` calls (measured against a planted `Sway::Settings.upstream.x == "y"` line), and the visitor walks a call chain's own receivers (`a.b.c` → `a.b` → `a`) down to its root to decide whether the whole chain is rooted at `Sway::Settings`.

`ALLOWED_SETTINGS_WRITE_PATHS` (`lib/sway/settings.rb`) and `ALLOWED_SETTINGS_WRITE_PREFIXES` (`lib/sway/settings/`) exist because the declaration directory itself, plus the assembly module beside it, legitimately write settings — `lib/sway/settings.rb` pins `Anyway::Settings.suppress_required_validations` and installs group instances for `with_app_config`. Neither is a setting write in the sense this guard cares about, but the file sits one path segment above where the directory-prefix check alone would otherwise catch it, so it needs its own explicit entry.
