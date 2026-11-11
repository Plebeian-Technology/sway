---
lat:
  mode: explanation
---

# Bill LLM schema initializer design

Why the bill categories, positions, and summary LLM response schemas are split into separate files and why their JSONSchemer::Schema objects are never frozen.

## Why the categories schema is separate (bill_categories_schema.rb)

`BILL_CATEGORIES_SCHEMA` describes the shape of the answer from the language-model call that only picks categories for a bill.

It deliberately does NOT make `categories` a required field in `bill_summary.json`: the two schemas are kept separate so summary JSON an operator pastes in by hand still passes.

## Why the schemas are read once at boot and never frozen

The rules are read once at boot from a schema file kept in this repo.

We do NOT call `.freeze` on the `JSONSchemer::Schema` object: json_schemer 2.5 updates its own internal caches while validating, so a frozen one raises `FrozenError` on the very first check. It is still hard to tamper with, because:

- Ruby prints a warning if anything reassigns `BILL_CATEGORIES_SCHEMA`, and
  the only thing that does is Rails reloading this file in development.
- The schema file itself is under version control.

This same design — loaded once at boot, `Schema` object never frozen — is shared by `config/initializers/bill_positions_schema.rb`, `config/initializers/bill_summary_schema.rb`, `config/initializers/source_kind_classification_schema.rb`, and `config/initializers/testimony_stance_classification_schema.rb`. Nothing reassigns `BILL_POSITIONS_SCHEMA`, `BILL_SUMMARY_SCHEMA`, `SOURCE_KIND_CLASSIFICATION_SCHEMA`, or `TESTIMONY_STANCE_CLASSIFICATION_SCHEMA` after boot either: initializers run once per process, and Rails does NOT re-run them on a code reload (an earlier version of this note claimed otherwise).

An earlier plan for `spec/config/bill_summary_schema_spec.rb` asked for a `.frozen?` assertion on `BILL_SUMMARY_SCHEMA`, to pin the constant's immutability. That check was dropped for the same reason the object is never frozen in the first place: asserting `.frozen?` would pin a state this constant must never be in.

## Why the positions schema is split from the summary schema

`BILL_POSITIONS_SCHEMA` describes the shape of the answer from the language-model call that reads hearing testimony and produces support/oppose positions.

It was split out of `BILL_SUMMARY_SCHEMA` so that call and the summary call (which no longer produces positions) are checked separately.

## What the summary schema is shared between

`BILL_SUMMARY_SCHEMA` is one shared checker for the shape of bill-summary JSON. Two places use it:

- the `paste_summary` controller action, for JSON an operator pasted in by
  hand
- `BillSummaryJob`, for what the language model sent back

## Why bill_positions.json's bounds are tested for drift against bill_summary.json

`draft_org_positions` and its two free-text fields (`org_name`, `summary`) originally had no bounds in either schema file.

What the model answers about is publicly submitted PDF text, up to 150,000 characters of it, and the validated payload goes straight into a serialized JSON text column — so the only limit actually in force was the adapter's `max_tokens`, a runtime setting rather than a contract in either schema. The bounds added (`MAX_DRAFT_POSITIONS`, `MAX_ORG_NAME_CHARS`, `MAX_POSITION_SUMMARY_CHARS`, see `docs/reference/bill-positions-prompt-limits.md`) are all far past any real Baltimore hearing, which runs to a few dozen organizations and a one-sentence rationale each.

The same `draft_org_positions` list is optional in `bill_summary.json`, the contract an operator's pasted body is checked against — so the same bounds are asserted on both files, not just the one the prompt builder reads from. Two schema files describing one column is a drift shape this area keeps paying for: a bound raised in one file and not the other would silently reopen the gap the bound was added to close.

The stance-word enum (`support`/`oppose`/whichever words are declared) is tested the same way, and for the same reason, but the stakes are different: `BillLlmProvisioning::DRAFT_POSITIONS` reads its list out of `bill_positions.json` and the controller prints that list back to an operator who sends a stance it does not know. A fourth word added to `bill_summary.json` alone would pass that schema on submit, then be refused by a controller whose message named only three words — while the same word sent through the model-generated path would already have been refused at the schema. The two files' enums are compared directly against each other, and against `BillLlmProvisioning::DRAFT_POSITIONS`, rather than exercised one at a time, so a change to one that is not mirrored in the other fails the moment it is made.

`cited_section_keys` was the one array in either schema file with no bound at all. `SummaryCitationValidator` (see `docs/explanation/citation-validator-design.md`) filters whatever a model or a pasted payload sends against the bill's parsed section keys and writes the remainder to `invalid_citations`, a column a polling admin surface reads every five seconds. On the paste path there is not even a `max_tokens` between an operator's body and that column. `MAX_CITATION_KEYS` and `MAX_METADATA_FIELD_CHARS` (see `docs/explanation/bill-summary-prompt-limits.md`) are the numbers the prompt can actually offer, so no honest answer is refused: `BillSummaryPromptBuilder::MAX_CITATION_KEYS` is the most DISTINCT keys the allow list can ever print, and `MAX_METADATA_FIELD_CHARS` is the longest key `#renderable_citation_key?` will print. The schema-level test for this bound has no repeats in its over-cap payload, so it still fails at 251 keys even though `Llm::ResponseNormalizer` would remove a REPEATED key before this check ever runs in the real pipeline (`Llm::ResponseNormalizer::NO_TRIM_FIELDS`) — that repair is pinned in `response_normalizer_spec.rb`, not in the schema spec.

`categories` had the same gap: a `maxItems` bound with no bound on the individual item, in both files that carry it. `Category::MAX_NAME_CHARS` is the length a `Category` record can hold, so a longer name could never match an active category anyway — refusing it at the schema costs nothing real.
