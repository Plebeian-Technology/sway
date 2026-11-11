---
lat:
  mode: explanation
---

# Why Sway::Settings::Base replaces Anyway::Config's casters

`Anyway::Config`'s own `:string`/`:integer`/`:float`/`:boolean` casters either keep the auto-cast damage (turning a phone list into an `Array`) or return a zero or `false` for unreadable text.

`Sway::Settings::Base` replaces all four so a whole number that is not a whole number stops the boot naming the setting, instead of silently becoming `0`.

The replacements are registered on `Anyway::TypeRegistry.default`, which is global and process-wide. Nothing else in this app uses the registry today, so that is contained, but the next reader cannot see that from the registration line itself.

## Integer: base 10, explicitly

`:integer!` already raises strictly in the gem; plain `:integer` does not (it is `.to_i`, which turns `"lots"` into `0`).

Both spellings are registered to the same strict block, because the RBS generator only maps the plain name to a typed `Integer` — `:integer!` generates `untyped`.

The caster calls `Integer(stripped, 10)` rather than bare `Integer()`, because bare `Integer()` honors Ruby's literal prefixes: a leading zero reads as octal (`"030"` becomes `24`) and `"090"` raises outright. That is the exact "silently becomes a different whole number" failure this caster exists to remove, just with a different wrong number.

## Float: format validated before Float() sees it

No built-in `:float!` exists; both spellings are added here for the same reason as `:integer` above.

`Float()` also honors a leading `"0x"` as hex (`"0x10"` becomes `16.0`), so the caster validates the format against `/\A[+-]?(\d+(\.\d+)?|\.\d+)([eE][+-]?\d+)?\z/` before `Float()` ever sees the value, rather than trusting its own leniency.

## Boolean: blank and unrecognized are not the same failure

The gem's own `:boolean` answers `false` for a blank value, which would silently switch a rate limit off instead of falling back to its declared default of on.

This caster answers `nil` instead, so `Base`'s `on_load` blank repair can restore the declared default.

It stays deliberately lenient about *unrecognized* non-blank text, though — reading it as `false` rather than raising. `Sway::Settings::Ops`'s backup-skip switch is tested to leave backups on for exactly this case: "missing, blank, and unreadable must ALL leave backups on... a misread that silently answers true is the worst outcome" — an explicit design decision, not an oversight. `DevLogin`'s and `Llm`'s switches have the same "unrecognized stays on the safe side" shape.

`DevLogin#skip_phone_verification` is the sharpest example of that shape: the old `ENV.fetch(...).present?` semantics treated ANY non-empty text as "skip", including the words `"false"` and `"0"`. Declaring the switch `:boolean` narrows it to the short list of recognized truthy words above — everything else, including unset, blank, `"banana"`, `"0"`, and the word `"false"` itself, now leaves the phone check ON. The new semantics are fail-closed even in a case where the old ones were not.

This registry entry is shared by every group (`Anyway::TypeRegistry.default` is process-wide), so it cannot raise for `RateLimits`'s ten switches without also raising for those three. `Sway::Settings::RateLimits` is where the actual risk this shape has — a `true`-default switch silently flipping to `false` on a typo — gets a raise instead, scoped to that one group by reading the raw env value directly rather than widening this shared caster.
