---
lat:
  mode: reference
---

# Testimony stance classification

JSON schema specification and validation constants for structured testimony letter stance classification.

## Payload schema specification

Field contracts and bounds for `config/schemas/testimony_stance_classification.json` validating structured LLM output in `Testimony::StanceClassifier`.

| Field | Type | Constraint | Description |
| --- | --- | --- | --- |
| `classifications` | Array | `required`, max 25 items | Ordered batch of letter stance verdicts keyed by letter index |
| `classifications[].position` | Integer | `required`, `>= 0` | 0-based index of the letter in the cleaned testimony letters array |
| `classifications[].stance` | String | `required`, enum | Position stance in `["support", "oppose", "neutral"]` |

## Schema constants and validators

Lookup constants loaded once at boot in `config/initializers/testimony_stance_classification_schema.rb`.

| Constant | Type | Description |
| --- | --- | --- |
| `TESTIMONY_STANCE_CLASSIFICATION_SCHEMA_HASH` | `Hash[String, untyped]` | Parsed and frozen JSON schema hash loaded from `config/schemas/testimony_stance_classification.json` |
| `TESTIMONY_STANCE_CLASSIFICATION_SCHEMA` | `JSONSchemer::Schema` | Unfrozen compiled JSONSchemer validator for runtime response validation |

## Adapter method contracts

Uniform adapter signatures across LLM providers for stance classification.

| Adapter | Method signature | Schema validation |
| --- | --- | --- |
| `Llm::OpenRouterAdapter` | `#generate_testimony_stance_classification(prompt:, model:, schema:, reasoning_effort: nil)` | `TESTIMONY_STANCE_CLASSIFICATION_SCHEMA` |
| `Llm::ClaudeAdapter` | `#generate_testimony_stance_classification(prompt:, model:, schema:)` | `TESTIMONY_STANCE_CLASSIFICATION_SCHEMA` |
| `Llm::LlamacppAdapter` | `#generate_testimony_stance_classification(prompt:, model:, schema:)` | `TESTIMONY_STANCE_CLASSIFICATION_SCHEMA` |

## StancePromptBuilder parameters and limits

Configuration parameters and truncation limits for `Testimony::StancePromptBuilder`.

| Constant / Parameter | Type | Value | Description |
| --- | --- | --- | --- |
| `MAX_LETTER_CHARS` | Integer | `2_000` | Maximum character length for letter body text before truncation |
| `HEAD_LETTER_CHARS` | Integer | `1_400` | Opening character window preserved when a letter exceeds `MAX_LETTER_CHARS` |
| `TAIL_LETTER_CHARS` | Integer | `600` | Closing character window preserved when a letter exceeds `MAX_LETTER_CHARS` |
| `MAX_EXTERNAL_ID_CHARS` | Integer | `200` | Maximum character length for sanitized bill external ID |
| `MAX_TITLE_CHARS` | Integer | `1_000` | Maximum character length for sanitized bill title |
| `MAX_SUMMARY_CHARS` | Integer | `4_000` | Maximum character length for sanitized bill summary |
| `TEXT_TRUNCATION_NOTICE` | String | `" [... truncated: this is the opening of the letter, not all of it ...]"` | Notice appended to truncated letter text |
| `STANCES` | Array | `["support", "oppose", "neutral"]` | Allowed stance classifications accepted from models |
| `letters:` | Array | `Array[Hash]` | Candidate letter list with position and text |
| `bill:` | Model / nil | `Bill?` | Optional bill instance supplying external_id, title, and summary |

## StanceClassifier constants and return values

Execution constants and return value structure for `Testimony::StanceClassifier`.

| Constant / Return | Type | Value | Description |
| --- | --- | --- | --- |
| `MAX_LETTERS_PER_BATCH` | Integer | `25` | Maximum number of candidate letters dispatched per model batch |
| `MIN_DECISION_CONFIDENCE` | Float | `0.5` | Minimum confidence required for OpenRouter decision model verdicts |
| `STANCES` | Array | `["support", "oppose", "neutral"]` | Normalized stance categories stamped on letters |
| `augmented_letters` | Array | `Array[Hash]` | Input letters enriched with `"stance"` in `{"support", "oppose", "neutral"}` |
| `counts` | Hash | `Hash[String, Integer]` | Stance counts hash containing `stance_support_count`, `stance_oppose_count`, `stance_neutral_count` |

## StanceRules constants and manual override keys

Deterministic lexical rules in `Testimony::StanceRules` and manual stance override metadata in `cleaned_testimony["letters"]`.

| Constant / Key | Type | Description |
| --- | --- | --- |
| `Testimony::StanceRules::POSITION_HEADER_LINE_PATTERN` | `Regexp` | Matches opening `Position:` and `Stance:` header lines |
| `Testimony::StanceRules::SUBJECT_HEADER_LINE_PATTERN` | `Regexp` | Matches opening `Subject:`, `Re:`, `Bill:`, and `Testimony:` header lines |
| `Testimony::StanceRules::OPPOSE_PATTERNS` | `Array[Regexp]` | High-precision opposition body patterns (`vote no`, `vote against`, `unfavorable report`, `do not pass`, `do not support`, `oppose this bill`, `in opposition`) |
| `Testimony::StanceRules::SUPPORT_PATTERNS` | `Array[Regexp]` | High-precision support body patterns (`vote yes`, `favorable report`, `favorable with amendments`, `pass this bill`, `support this bill`, `in support`) |
| `letter["stance_override"]` | `Boolean` | True when an admin manually overrides a letter's stance or excludes a letter via `PATCH /bills/:id/testimony_letter_stance`; preserved across `Testimony::CleanAndGroupService` runs |
| `letter["excluded"]` | `Boolean` | True when an admin manually removes a letter from testimony via `PATCH /bills/:id/testimony_letter_stance`; skipped by `Testimony::StanceClassifier` and `Testimony::OrganizationEntityExtractor`, and excluded from `Testimony::BrowsableLetters`, `BillPositionsPromptBuilder`, `Testimony::CoverageReport#individual_letter_count`, `BillsController#compute_cleaned_testimony_derivation`, and stance counts |
