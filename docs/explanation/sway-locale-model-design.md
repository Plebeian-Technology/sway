---
mode: explanation
summary: "Explains SwayLocale's computed-name lookup methods, why normalize_attributes moved out of after_initialize, why declared_jurisdiction_rules degrades instead of refusing, and why #legislators filters on sway_locale_id directly."
status: agent-extracted
related: [jurisdiction-rules-design, term-rules-design, legislator-person-not-seat]
---
<!-- vale Vale.Spelling = NO -->

# SwayLocale model design notes

## Why get_by_name and resolve_by_computed_name are two different lookups

`SwayLocale#name` is built on the fly (`"city-region-country"`, each piece
run through `format_name`). There is no `name` column, so
`find_by(name:)` raises `ActiveRecord::StatementInvalid`.

`get_by_name` splits the string apart and queries the raw `city`/`state`/
`country` columns. It misses whenever the stored `state` or `country` is
in a different form than the normalized one (`"MD"` against `"maryland"`).

`resolve_by_computed_name` compares the fully built name on both sides
instead, loading every row — fine, because the locales table is tiny —
and is shared by the Baltimore locale lookups where `get_by_name`'s gap
would bite. Its name starts with `resolve_`, not `find_by_`, because the
`find_by_` prefix makes the `Rails/DynamicFindBy` rubocop rule rewrite
call sites into `find_by(computed_name:)` — a column that does not exist.

## Why normalize_attributes exists as its own method

`find_or_create_by_normalized!` puts `{city, state, country}` into the
same standard form the `before_validation` `nameify_*` callbacks produce,
without building a record to get there. The finder used to lean on
`SwayLocale.new(kwargs)` firing `after_initialize`, but that callback also
ran on every load and marked already-saved rows as changed, so
normalization moved to `before_validation` and the finder needed its own
copy. Nil values are safe in `normalize_attributes`, because `format_name`
raises on nil rather than silently passing one through.

## Why declared_jurisdiction_rules degrades instead of refusing

`#term_rules` and `#jurisdiction_rules` both raise their registry's
`Undeclared` error for a locale with no entry — see
[term-rules-design.md](term-rules-design.md) and
[jurisdiction-rules-design.md](jurisdiction-rules-design.md) for why that
refusal is deliberate.

`#declared_jurisdiction_rules` is the one exception, and only for the
naming fields: it returns `nil` instead of raising when the locale has no
entry. These fields go out in the payload shared with every page, for
every locale a reader belongs to — and registration creates a row for the
reader's city AND state, so readers outside a supported jurisdiction carry
locales nobody has declared. Refusing there would take down every page
for those readers, to avoid showing one wrong word. The name goes out
empty instead, and the screen asks rather than guessing.

The `to_builder` fields that read through it follow the same pattern:
`default_bill_chamber` and `bill_chambers` are both `nil` for an
undeclared locale, so the Bill Creator stops guessing "council" for a
locale with no council, and instead leaves the chamber picker and the
senate-vote-date field editable for a reason it can state.

## Why #legislators filters on sway_locale_id, not through district

`#legislators(active = true)` narrows by the `sway_locale_id` column on
`legislators` directly. Reaching the locale through the district instead
would INNER JOIN by way of the current term and quietly drop any
legislator with no current term before the locale filter even ran.
"Active" comes from the term instead — `Legislator.serving`, which
replaced the dropped `active` column — rather than a plain boolean WHERE.

`User#user_legislators_by_locale` follows the identical pattern for the
same reason: it narrows by the `sway_locale_id` column on `legislators`
directly, rather than reaching the locale through the district, because
that path would also INNER JOIN by way of the current term and silently
drop any legislator with no current term before the locale filter runs.

## Why to_builder sends districts: nil

`SwayLocale#to_builder` sends `s.districts nil` deliberately: the
frontend's `ISwayLocale` type and the bootstrap spec both expect a
`districts` key in this payload, but the client fetches districts
separately, so the key is present with no value rather than absent.

## Why `FetchBillsService#resolve_baltimore_locale` layers a `find_by` before the computed-name fallback

`FetchBillsService#resolve_baltimore_locale` looks up
`SwayLocale.find_by(city: "baltimore", state: "maryland")` before falling
back to `SwayLocale.resolve_by_computed_name`. `find_by(city:, state:)`
includes `state:` so that adding another city with the same name later — a
Baltimore, OH, say — cannot match `city: "baltimore"` at random.

It falls back to `resolve_by_computed_name` rather than
`find_by(name: ...)` because `SwayLocale#name` is worked out in Ruby, not
stored as a database column (see above): asking the database for it raises
`SQLite3::SQLException: no such column: name` — a bug the `||` hid for as
long as the `city:` lookup kept matching.

The locale-name string this fallback resolves lives in exactly one place,
`LegislationIngestionService::DEFAULT_LOCALE_NAME`. A second copy used to
sit in `FetchBillsService`, and a contributor changing one and not the
other would have let them drift apart without anyone noticing.

`FetchBillsService` raises `StageError` when no locale is found — the same
error class `FetchLawService#resolve_locale` uses, which is what makes the
orchestrator's `run_run_level_stage` rescue route it through
`handle_run_failure`. The lookup happens up front, before the
database-writing loop, so a missing locale fails immediately instead of
surfacing later as a `RecordInvalid`.

`FetchBillsService#sway_locale_name` (the name every artifact path in that
service is filed under) memoizes this same lookup — `#persist` runs once
per bill, and without memoizing, that would be one extra locale lookup per
bill for a value that cannot change inside a run. Reading it there rather
than threading it through `#persist` is honest about what that service is:
the discover path is wired to Baltimore (`Legistar::Client`'s
`DEFAULT_CLIENT`). When a second jurisdiction arrives, this accessor is the
one place that has to start varying.
