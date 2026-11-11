---
mode: explanation
summary: "Explains why Llm::StructuredOutputSchema strips unsupported JSON Schema keywords before calling Anthropic, and the two production defects that shaped its map-keyed-keyword handling and cache-keying strategy."
status: agent-extracted
related: [docs/reference/llm-structured-output-schema-stripping.md]
---

# Why Llm::StructuredOutputSchema strips keywords, and the defects that shaped it

<!-- vale Vale.Spelling = NO -->

See also `docs/reference/llm-structured-output-schema-stripping.md` for the
exact keyword lists and cache bound.

## Why stripping exists at all

Anthropic's docs say the Python and TypeScript SDKs strip unsupported JSON
Schema keywords before sending a structured-output request; the Ruby SDK
isn't documented to, and `ClaudeAdapter` used to pass the raw schema hash
straight through. Three of the four schemas this app sends carried such
keywords — `bill_summary.json`, `bill_categories.json`, and
`testimony_classification.json`; `bill_positions.json` was already clean.

This makes no claim about what the API actually does with an unsupported
keyword — nobody has called live to find out. Ignoring them is harmless if
so; rejecting them with a 400 would break every call if not. Stripping
costs nothing either way, so it happens regardless of which is true.

## Why a property named like a keyword must not be deleted

An earlier version of `#strip` deleted keys by name at every depth, without
asking whether a key sat in KEYWORD position or was a PROPERTY NAME. A
schema declaring a property literally called `minimum` lost that property
from `properties` under that logic — and the sent schema then `require`d a
field it also forbade via `additionalProperties: false`. Every call using
that schema would have failed invisibly, with `CACHE` holding the broken
copy for the rest of the process's life.

`SCHEMA_MAP_KEYWORDS` — the list of keywords whose value is a
property-name-keyed map — once missed `dependentRequired` and
`dependencies`, both keyed by property name. A dependency keyed on a
property named like an unsupported keyword got deleted under the old logic,
in the dangerous direction: silently narrowing what the schema allows, not
just what it validates. The `JSONSchemer` checker still enforces that
dependency against the response, holding the model to a rule the sent
schema never actually mentioned. None of the four shipped schemas hits this
today; the module exists for the fifth.

## Why data values are walked differently

`#strip` also has to recognize keys sitting INSIDE data, not just inside
schema structure. A key inside an `enum`/`const`/`default`/`examples` value
is part of what the response must match — deleting it would rewrite the
rule the schema expresses, not loosen a limit. `DATA_VALUE_KEYWORDS`'
values are deep-copied rather than walked, specifically so a shared subtree
can't let a later mutation land back in a frozen boot constant.

## Why the cache is keyed by object identity, not schema contents

`CACHE` is keyed by identity (`compare_by_identity`) because the four
schema hashes are frozen constants built once at boot and reused on every
LLM call — hashing the whole schema deeply on every request would be pure
waste on the single Raspberry Pi that runs production.

A prior version used ordinary value-based `Hash` keying, which was removed
in favor of identity keying on the stated justification that a per-request
(not frozen-at-boot) schema would otherwise pile up unboundedly in the
cache. That justification was backwards: identity keying does NOT make a
per-request schema merely miss the cache instead of piling up — a miss
doesn't stop the insert that follows it, so a per-request schema still
misses AND inserts a new entry on every single call, forever. Value-based
keying, the approach that got removed, would actually have HIT on an equal
schema and grown nothing. The switch made the risk its own comments
described worse, not better, while the comments kept describing it as
handled.

`MAX_CACHE_ENTRIES` (64) is what actually bounds growth today, regardless
of keying strategy — deliberately clear-everything-and-refill rather than
LRU, since a clear only costs re-walking the four boot schemas in
microseconds.

64 is far more than the four schemas built at boot and far less than
anything that matters for memory on the small production host. A per-request
caller now churns through the cache instead of leaking.

## Why `DATA_VALUE_KEYWORDS`' four keywords hold different shapes

`enum` and `examples` hold arrays of such values; `const` and `default`
hold one each. Either way the whole value is returned as-is (deep-copied,
never walked).

## Why `.for_request`'s `built` local is declared, not asserted

`#strip` walks arbitrary JSON, so its declared return type is the widest
one. A `Hash` in always means a `Hash` out, but the type checker can't see
that through a recursive walk.

Declaring the local variable (`@type var built: Hash[String, untyped]`) is
the form that takes effect here; a trailing `#:` assertion does not.
`GenerateBillSummaryService` writes up the same trap — see
[generate-bill-summary-service-concurrency.md](generate-bill-summary-service-concurrency.md).

## `.strip`'s contract: containers copied, keywords removed, scalars shared

`.strip` pays attention to WHERE a key sits, not only what it's called — a
property named `minimum` is a property, not a limit, and a key inside an
enum/const/default/examples value is part of what the response must
match, not schema structure. Every container is rebuilt; those data
values are deep-copied, other leaf scalars are shared with the caller
(safe only because nothing mutates them — the schema constants are frozen
at the top level only).
