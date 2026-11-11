---
mode: reference
summary: "Lists which JSON Schema keywords Llm::StructuredOutputSchema strips for Anthropic's structured-output API, how map-keyed and data-valued keywords are handled, and the identity-keyed cache bound."
status: agent-extracted
related: [docs/explanation/llm-structured-output-schema-defects.md]
---

# Llm::StructuredOutputSchema stripping rules

<!-- vale Vale.Spelling = NO -->

`Llm::StructuredOutputSchema` makes a copy of a JSON Schema hash that is
safe to send to Anthropic's structured-output feature. For why each rule
exists and the defects it fixes, see
`docs/explanation/llm-structured-output-schema-defects.md`.

## Supported subset

Anthropic's structured-output feature supports basic types, `enum`,
`const`, `anyOf`, `allOf`, `$ref`/`$defs`, named string formats, and
`additionalProperties: false`. Numeric, string-length, and array-length
limits are NOT supported.

## Keywords stripped everywhere (`UNSUPPORTED_KEYWORDS`)

`minLength`, `maxLength`, `pattern`, `minimum`, `maximum`,
`exclusiveMinimum`, `exclusiveMaximum`, `multipleOf`, `minItems`,
`maxItems`, `uniqueItems`.

`format` is left in (it's supported); `$schema`, `title`, and `description`
are left in too — stripping something needed is worse than leaving
something ignored.

## Keywords whose value is a property-name map (`SCHEMA_MAP_KEYWORDS`)

`properties`, `$defs`, `definitions`, `patternProperties`,
`dependentSchemas`, `dependentRequired`, `dependencies`.

`#strip` descends only into the VALUES of these maps — the keys are
property names, never checked against `UNSUPPORTED_KEYWORDS`.
`propertyNames`/`unevaluatedProperties`/`additionalProperties` hold a single
subschema rather than a name-keyed map, so `#strip`'s default branch
(recurse into the value) is already correct for those and they aren't
listed here.

## Keywords whose value is data, not a subschema (`DATA_VALUE_KEYWORDS`)

`enum`, `const`, `default`, `examples`.

`#strip` does not walk into these values at all — the whole value is
deep-copied (`Object#deep_dup`) and returned as-is. A `minimum` key inside a
`const` value is part of the value the response must match, not a limit to
strip.

## What "copy" means

Every `Hash`/`Array` container `#strip` walks is rebuilt; `enum`/`const`/
`default`/`examples` values are deep-copied. Plain scalars reached in leaf
position (outside any `DATA_VALUE_KEYWORDS` value) are handed back as the
caller's own objects — safe only because nothing mutates them afterward,
not because they're independently protected. The four schema constants
(`bill_summary.json` etc.) are frozen at the top level only; strings nested
inside are shared and mutable.

## Response checking is unaffected

`JSONSchemer` checkers are built from the ORIGINAL, unstripped hashes and
enforce every limit — `minLength`, `maxItems`, and the rest — against the
model's response. Stripping changes only what's sent to Anthropic, never
what's checked afterward.

## Cache

`.for_request(schema)` caches the stripped result in `CACHE`, a
`Hash#compare_by_identity` keyed by the schema object itself (not its
contents) — the four schemas are frozen boot constants reused on every
call, so identity keying is exact for every caller today. `CACHE` clears
and starts over once `CACHE.size >= MAX_CACHE_ENTRIES` (64); re-walking the
four boot schemas after a clear costs microseconds. Access is serialized
through `MUTEX`.
