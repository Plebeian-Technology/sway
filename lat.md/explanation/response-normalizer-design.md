---
lat:
  mode: explanation
---

# Why Llm::ResponseNormalizer exists, and what it does and does not fix

`Llm::ResponseNormalizer` tidies up a model's answer to make up for a lopsidedness that `Llm::StructuredOutputSchema` introduced.

`StructuredOutputSchema` strips keywords Anthropic calls unsupported from the schema sent to the model, while the `JSONSchemer` checkers that inspect the answer still use the ORIGINAL, unstripped hashes. See [[docs/explanation/llm-structured-output-schema-defects.md|llm-structured-output-schema-defects.md]] for that stripping design.

## The risk that motivated this file

`StructuredOutputSchema`'s own risk write-up listed two outcomes for those stripped keywords — quietly ignored (harmless), or rejected at compile (every call 400s) — but not a third: accepted and obeyed.

Under that third one, stripping left GENERATION less constrained while CHECKING stayed strict. Nobody has established which is real; this file removes the consequence instead of the question.

## Why the consequence is expensive and one-sided

The consequence is expensive and one-sided. `bill_summary.json` allows at most 3 `categories`, and that's now missing from the request. A model returning four fails the check and gets discarded.

Because `parse_and_validate` runs BEFORE `provisioning.update!`, the whole paid-for summary is lost and the row ends up `failed`. Dropping a fourth category beats losing the whole summary with it.

## What gets fixed up and what does not

The dividing line: does degrading lose only surplus, or does it change what the answer MEANS?

- **`maxItems` → FIXED.** Every field trims to the first N.
  `cited_section_keys` is the one exception: it removes repeats instead of
  trimming by position. See `NO_TRIM_FIELDS` and `#cap_items` below.
- **`maxLength` → not fixed.** Cutting a `summary_markdown` off
  mid-sentence produces a record that looks fine and is quietly wrong. No
  schema uses it; the fix is a prompt that asks for less.
- **`minimum` / `maximum` → not fixed.** `testimony_classification.json`
  requires `index >= 0`; pulling a negative index up to 0 would apply the
  model's verdict to a DIFFERENT attachment. Failing is correct.
- **`minLength` / `minItems` / `pattern` / `uniqueItems` / `multipleOf` →
  not fixed.** Nothing to degrade to: the model returned nothing usable,
  and inventing content to satisfy a limit is making things up.

`$ref` / `$defs` / `anyOf` subschemas are stepped over, not followed — none of the four shipped schemas uses them, and half-following references is worse than plainly not.

## NO_TRIM_FIELDS: why it exists as a name-keyed list, and why it's checked at load

Fields `#cap_items` repairs by removing repeats instead of trimming by position. Keyed by field name, not schema, so the same name means the same thing everywhere it appears — see the `#cap_items` section below for why.

The `.fetch` calls right after the constant die at load time, not the first LLM call, if a schema rename ever drops a property this list names. Without this, `#cap_items` would quietly stop matching that field by name.

Every spec written for this would still pass: two build their own schema literal and never see the rename; the rest still raise — but from `additionalProperties: false`, not from this guard.

`BillLlmProvisioning::DRAFT_POSITIONS` and `BillSummaryPromptBuilder::MAX_CATEGORIES` fetch their way down a schema hash for the same reason.

## cap_items: quietly changing a response is how earlier bugs went unnoticed — say so

`NO_TRIM_FIELDS` gets a different repair, not none. Everywhere else, a `maxItems` trim removes surplus. The schema allows N, the model sent more, and the first N are as good a pick as any.

Position does not work for `cited_section_keys`. `SummaryCitationValidator` checks this field AFTER this step runs. A fabricated key past a position cut would disappear before that check ever sees it.

Not rejected, not logged, invisible — the row would then record `citations_valid: true` for a body nobody had actually checked.

A repeated key is safe to remove, and removing it is the repair. `SummaryCitationValidator` calls `.uniq` before checking anything, so a second copy of a key already present gives that check nothing new.

Dropping the repeat loses only surplus, the same as an ordinary `maxItems` trim — it cannot hide a fabricated key, because that key's first copy is still in the array the check sees.

A list still too long AFTER de-duplication still fails schema validation. That is the same refusal `PasteSummaryService` already gives an operator who pastes one.

It is the guarantee that was asked for: the two writers of `citations_valid` must agree on the same body. The allow-list can never offer more than 250 DISTINCT keys, and a repeat doesn't count twice.

## dedupe: NO_TRIM_FIELDS' one repair

The dedupe step removes exact repeats and keeps everything else. See `#cap_items` above for why this is safe where a position trim is not.
