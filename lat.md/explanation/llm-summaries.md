---
lat:
  mode: explanation
---
# LLM bill summaries

A bill's plain-language summary is generated, not written. `app/services/llm/` is a small adapter layer that keeps the generation swappable, checkable and cheap to run in development.

## Two adapters, one client

`Llm::Client.build` returns `Llm::ClaudeAdapter`, `Llm::LlamacppAdapter`, or `Llm::OpenRouterAdapter`, chosen from an allowlist of three strings. Anything else raises rather than falling through to a default.

Production uses the Claude API. Development and test point at a llama.cpp
server running on the host, reached at `host.docker.internal:8888`. The split
is not about model quality — it is that bill seeding invokes summarisation
repeatedly, and billing an API call for every iteration of a local seed run
would make the development loop expensive to use. The third provider,
OpenRouter, reaches non-Anthropic models with `data_collection: "deny"`,
`require_parameters: true`, and serving-upstream attribution without a
three-company pin.

[[app/services/llm/open_router_adapter.rb#Llm#OpenRouterAdapter|OpenRouter credential access]]
uses the canonical runtime secret name first and accepts the vault's existing
underscore spelling in development and test. Kamal already maps that spelling
to the canonical name at deployment. Both pass through
[[app/lib/env_secret.rb#EnvSecret|the application's secret reader]]; no adapter
reads private files or logs credential values.

The provider is re-read per call rather than memoised, so an operator switching
provider does not need a restart to see the change.

### Unknown models are uncacheable by default

A model whose token caching prefix threshold is unknown is treated as uncacheable. `Llm::PromptCache.cacheable?` logs a warning and returns false when queried with an unrecognised model identifier.

`minimum_prefix_tokens(model)` returns nil for models not explicitly registered in its threshold table. In earlier iterations, `cacheable?` defaulted to true when the threshold was nil, causing callers to treat unknown models as supporting prompt caching without verification. Returning false prevents invalid caching assumptions while `SwayLogging.warn` alerts operators to evaluate the uncataloged model.

### The live check against a local server is a task, not a test

A rake task runs a real summary against a running llama.cpp server, and no
automated suite runs it.

The suite replays recorded HTTP exchanges so its results stay repeatable, which
is the right property for a test and the wrong one for proving an integration
works. The task is the live check a person runs before calling the work done,
and keeping the two apart is what stops either from quietly standing in for the
other.

### The job never names an SDK

`GenerateBillSummaryJob` is provider-agnostic by contract, not by convention: outside its comments its source names no vendor SDK constant, and `spec/integration/source_file_isolation_spec.rb` greps the file to keep it so.

The rule runs one way only. A vendor constant belongs in the adapter layer, so the same spec asserts one is present there. That counter-assertion is what stops the grep passing merely because the string it searches for has stopped existing anywhere in the codebase.

It reads `app/services/llm/claude_connection.rb` rather than the adapter itself, because `Anthropic::Client.new` sits in the connection seam the direct and batch Claude paths share. A reader who expects the adapter to name its own SDK will find that it delegates instead.

### What the local server is asked for, and how long it is given

The request to the local server asks the chat template not to emit thinking tokens, and allows far longer than a hosted call would.

A local reasoning model spends its whole `max_tokens` budget thinking and
returns nothing usable, so the flag is asserted on the wire rather than through
a constant — measured, the constant proved not to matter and the wire value did.
The generous timeout is about the machine rather than the model: several agents
share one llama.cpp server on the host, so a request can wait in somebody else's
queue before it is started at all, and grammar-constrained generation is the
slow one that timed out first.

## Planned OpenRouter model choices

Sway supports twelve baseline models alongside customizable OpenRouter models dynamically fetched through [[app/services/llm/open_router_models_service.rb#Llm#OpenRouterModelsService]], with searchable comboboxes and reasoning effort controls.

The baseline selector choices defined in [[app/models/admin_setting.rb#AdminSetting|AdminSetting::SUPPORTED_MODELS]] include three direct Claude tiers (`claude-haiku-5-5`, `claude-sonnet-5-5`, `claude-opus-5-5`) and nine baseline OpenRouter choices (`Opus Latest`, `Sonnet Latest`, `Haiku Latest`, `Gemini Argon Latest`, `Gemini Flash Latest`, `GLM Latest`, `Deepseek Pro Latest`, `Deepseek Flash Latest`, `OpenRouter Auto`). Beyond the baseline set, administrators can dynamically add or remove offered models discovered via `Llm::OpenRouterModelsService`.

Both the standing settings page (`/admin/llm_settings`) and the Bill Creator summary tab (`/admin/bill_creator/{bill_id}/summary?tab_key=summary`) provide searchable comboboxes that filter available options by label or underlying slug. When a chosen model supports reasoning, both surfaces present reasoning effort controls with `default`, `low`, `medium`, and `high` options.

The existing model-only settings values and per-run parameter identify the choice. A server-side catalog supplies its adapter and API model identifier; the shared resolver selects a consistent pair before adapter construction. An OpenRouter choice takes precedence over the legacy environment provider, routing to OpenRouter across all environments including local development. Existing Claude choices retain their environment branching, routing to production Claude or local llama.cpp.

The per-run summary choice remains serialized with the job and cannot change the standing default or classification model. Ordinary summary calls handle OpenRouter selections even when the Anthropic batch toggle is enabled. Already-submitted Anthropic batches retain their original route through ingestion and retry, so a later settings change cannot send an OpenRouter model to Anthropic.

## What a third provider reached through OpenRouter exposes

A non-Anthropic model is reached through OpenRouter, never directly. OpenRouter is a router: one model id is served by many upstream companies, so an unpinned route is a different set of companies every day.

This matters because the text sent for a positions call includes Baltimore hearing testimony, which carries private residents' names, home addresses and personal email addresses. The question of who may receive that text is a privacy decision about companies, not a decision about models.

The scale of the question was measured live against the OpenRouter API for the candidate model `deepseek/deepseek-v4-flash-0731`. Twenty-nine upstream endpoints serve it: OpenInference, Relace, Baidu, DigitalOcean, DeepInfra, Ambient, Makora, Morph, GMICloud, BaseTen, Inceptron, CoreWeave, AkashML, Parasail, Together, Mancer 2, Venice, Alibaba, DeepSeek, StreamLake, Fireworks, Reka, Phala, SiliconFlow, Wafer, Novita, NextBit, AtlasCloud and Cloudflare.

### Strict JSON is a property of the endpoint, not of the model

Eight of those twenty-nine do not advertise `structured_outputs` in their supported parameters: Relace, DigitalOcean, GMICloud, BaseTen, CoreWeave, DeepSeek, StreamLake and Novita.

Sway's summary and positions calls both demand a JSON Schema with `additionalProperties` set to false, so a route pinned to one of those eight answers without the constraint production relies on. A schema-failure count measured against such a route says something about the endpoint rather than about the model.

Context length varies across the same set: most report 1,048,576 tokens, while CoreWeave and Reka report 262,144 and Makora, Venice and Alibaba report 1,000,000.

### The measured price, and why an older figure is not used

The registry reported `deepseek/deepseek-v4-flash-0731` at $0.05 per million prompt tokens, $0.10 per million completion tokens and $0.010 per million cache-read tokens. The floating alias `~deepseek/deepseek-v4-flash-latest` is a separate registry entry at $0.03, $0.10 and $0.007.

An earlier planning estimate of $0.03 input and $0.075 output was superseded by that measurement. The conclusion it supported survives the correction: an 87,000-token positions call costs about half a cent, not four cents, so cost is not what decides whether a second provider is worth having.

### Companies permitted to receive Baltimore hearing testimony

Sway routes OpenRouter requests with zero data collection and parameter enforcement, verifying serving attribution on completion.

Baltimore hearing testimony processed during bill position analysis contains unredacted citizen letters submitted to legislative committees. On Baltimore City Council Bill 62 alone, the input contains 439 signed constituent letters including full legal names, residential home addresses, and personal email addresses. While Anthropic processes text under a zero-retention data protection agreement and local development executes on private hardware, OpenRouter acts as a multi-tenant routing broker.

Outbound OpenRouter requests enforce privacy and parameter constraints without restricting routing to a hardcoded three-company list. Every outbound request specifies:

```json
"provider": {
  "data_collection": "deny",
  "require_parameters": true
}
```

OpenRouter's `data_collection: "deny"` filter excludes endpoints identified as collecting prompt text, preserving constituent privacy during position analysis across offered models. The `require_parameters: true` filter ensures only endpoints supporting strict JSON schema parameters receive requests.

[[app/services/llm/open_router_adapter.rb#Llm#OpenRouterAdapter|The adapter]] verifies unambiguous serving upstream company attribution on every completed response (`@last_upstream_company`), rejecting responses with missing, blank, or conflicting attribution claims.

### Server-side model catalog and exact model identifiers

The [[app/services/llm/model_catalog.rb#Llm#ModelCatalog|server-side catalog]] maps stored choices to exact request identifiers. Compatibility keys remain valid settings values; unknown choices raise rather than guessing a route.

The nine baseline OpenRouter choices map to canonical API identifiers:

- Opus Latest requests `~anthropic/claude-opus-latest`.
- Sonnet Latest requests `~anthropic/claude-sonnet-latest`.
- Haiku Latest requests `~anthropic/claude-haiku-latest`.
- Gemini Argon Latest requests `google/gemini-4-argon`.
- Gemini Flash Latest requests `~google/gemini-flash-latest`.
- GLM Latest requests `~z-ai/glm-latest`.
- Deepseek Pro Latest requests `~deepseek/deepseek-pro-latest`.
- Deepseek Flash Latest requests `~deepseek/deepseek-flash-latest`.
- OpenRouter Auto requests `openrouter/auto`.

The registry targets for Deepseek were `deepseek/deepseek-v4-pro-0813` and
`deepseek/deepseek-v4.1-flash`. Their endpoint records advertise structured
outputs through Together for Pro, and Together and Fireworks for Flash.
DeepSeek's own endpoints advertise neither structured outputs nor response
format. Parameter enforcement therefore matters even within the approved list.
([Pro endpoints](https://openrouter.ai/api/v1/models/deepseek/deepseek-v4-pro-0813/endpoints),
[Flash endpoints](https://openrouter.ai/api/v1/models/deepseek/deepseek-v4.1-flash/endpoints))

The leading tilde is part of OpenRouter's Latest alias syntax. Requests retain
the alias; the response reports the concrete model, which can change without a
Sway release. Calling the obsolete identifiers without the tilde returned 404
from the endpoint API. Replacing them with a dated concrete model would defeat
the chosen Latest behavior.
([Latest resolution](https://openrouter.ai/docs/guides/routing/routers/latest-resolution))

Auto's registry entry has no fixed endpoints. Its public contract describes
dynamic model selection, with the actual model returned in each response.
Public capability declarations alone do not prove an Auto request succeeds
under Sway's recipient, parameter and data-policy filters. The dated live
observations below confirm that the sampled Auto calls completed under those
filters; they do not establish a permanent model or upstream for Auto.
([Auto router](https://openrouter.ai/docs/guides/routing/routers/auto-router))

Direct API slugs and hyphenated aliases resolve to the same route definitions. The catalog also registers currently offered Claude models (`claude-haiku-5-5`, `claude-sonnet-5-5`, `claude-opus-5-5`) and preserves retired historical models (`claude-sonnet-4-6`, `claude-sonnet-4-5`, `claude-opus-4-8`) for persisted database settings. Lookups perform exact string matching without wildcards or prefix heuristics; unknown model strings return `nil`.

Beyond statically registered routes, dynamic model resolution enables administrators to select newly offered structured-output models from `Llm::OpenRouterModelsService`. When the cache is cold, a fallback tier inspects persisted models on `AdminSetting` with valid slug syntax, ensuring background workers and pipeline jobs continue operating without interruption.

Catalog definitions exist independently from `AdminSetting::SUPPORTED_MODELS`. The server-side routes are defined ahead of UI selector activation so downstream adapters and resolvers can be developed and verified before new choices are offered to operators.

### Dynamic OpenRouter model discovery and caching

Sway queries OpenRouter's model catalog dynamically so administrators can adopt new structured-output models without code changes or deploys.

[[app/services/llm/open_router_models_service.rb#Llm#OpenRouterModelsService|Llm::OpenRouterModelsService]] queries OpenRouter's public endpoint with `supported_parameters=structured_outputs` and normalizes the models into an alphabetized catalog. Because Sway uses structured JSON schemas for bill summaries, categories, and positions, models lacking structured output capabilities are filtered out at the service boundary.

Cached entries are persisted in Solid Cache (`Rails.cache`) on SQLite with a 12-hour TTL. Using SQLite-backed Solid Cache guarantees that background queue workers (`SolidQueue`) and web processes (`Puma`) share the cached catalog without requiring in-memory Ruby globals or dedicated Redis infrastructure.

When OpenRouter is unreachable, times out, or returns invalid payloads, the service logs a warning via `Rails.logger.warn` and returns a fallback (either previously cached stale models or an empty array). This ensures administrative pages and background workers never crash due to third-party availability hiccups. Manual refresh can be triggered by passing `force_refresh: true`. Full constants, schemas, and filtering specifications are documented in [[open-router-models#OpenRouter models catalog]].

### Resolving an inference route from the chosen model

The selected model determines the inference adapter before the request is built. OpenRouter choices route to OpenRouter regardless of ambient environment defaults.

[[app/services/llm/route_resolver.rb#Llm#RouteResolver|The resolver]] selects an adapter and API model from purpose, standing settings, blank fallbacks and optional summary overrides. A classifier retains that resolved model when its adapter is built.

For OpenRouter choices, the resolver returns `provider: :openrouter` in all environments, ensuring a local llama.cpp development server cannot intercept or block an OpenRouter inference run. For Claude choices, the resolver preserves legacy environment branching: returning `provider: :claude` in production (`Sway::Settings.llm.llm_provider == "claude"`) and `provider: :llamacpp` with `Sway::Settings.llm.llamacpp_model` in development.

Per-run overrides for `:summary` must appear in the active allowlist (`AdminSetting.offered_models` or the provided `setting.offered_models_list`), evaluated lazily so non-summary purposes avoid database reads. If a queued job or request specifies an inactive catalog choice or unoffered string, the override is refused and execution falls back to the standing database setting. Purpose `:classification` ignores per-run overrides, reading `classification_model` with a caller-supplied fallback when blank. Specialized purposes `:decision` and `:extraction` resolve `decision_model` and `extraction_model` respectively (defaulting to baseline entries), tagging `Route#mode` and predicates without reasoning effort. If a resolved model choice is absent from the catalog, the resolver raises `Llm::UnknownRouteError` rather than defaulting to local execution.

### Strict JSON conformance on the pinned route

Strict request schemas and local validation reject malformed answers. Advertised structured-output support is a capability claim; conformance rates require dated observations of the actual requested and served routes.

[[spec/integration/llm/openrouter_adapter_integration_spec.rb|The guarded harness]]
checks the real bill-summary and bill-positions schemas separately for every
choice. Its deterministic checks inspect the schema actually handed to the
request, including refusal of additional object properties. Live observations
identify requested alias, response model, serving upstream and per-schema
first-attempt, retry and failure counts. They describe the sampled calls, not a
universal success guarantee.

The authorized live run used
synthetic fixtures. It made two identical summary calls and one positions call
per choice: nine application calls, all schema-valid. Each schema's initial
call succeeded; no schema retry was needed. The repeated summary call also
validated for every choice. The first/retry/failure counts below concern
application schema attempts; gateway provider-attempt counts were not reported.

| Requested API model | Actual response model | Serving upstream | Summary first/retry/failure | Positions first/retry/failure |
| --- | --- | --- | --- | --- |
| `~deepseek/deepseek-pro-latest` | `deepseek/deepseek-v4-pro-0813` | Together | 1/0/0 | 1/0/0 |
| `~deepseek/deepseek-flash-latest` | `deepseek/deepseek-v4.1-flash` | Fireworks | 1/0/0 | 1/0/0 |
| `openrouter/auto` | `deepseek/deepseek-v4-flash-0731` | Together | 1/0/0 | 1/0/0 |

All accepted calls retained the recipient allowlist, disabled fallback,
data-collection refusal and parameter enforcement. The live spec finished
with four examples and no failures. These are observations of small fixtures,
not measurements of summary accuracy or a promise of universal conformance.
Ordinary verification skips paid inference.

### Settled schema keyword stripping for OpenAI-shaped requests

Outbound schemas use a conservative validation subset for Anthropic and OpenAI-compatible requests. Dialect caches remain isolated; full local validation still enforces constraints omitted from the wire schema.

[[app/services/llm/structured_output_schema.rb#Llm#StructuredOutputSchema|The schema transformer]]
currently omits the same constraint keywords for both dialects and caches them
separately. This records Sway's chosen interoperable subset, rather than
claiming every OpenAI-compatible endpoint rejects those keywords. Responses
still pass the original local schema before acceptance.

### Prompt caching measurement on the pinned OpenRouter route

OpenRouter requests omit Sway's Anthropic cache markers. Cache usage is measured per requested alias and served model/upstream; a price or usage object alone does not establish a cache hit or stable threshold.

[[app/services/llm/open_router_adapter.rb#Llm#OpenRouterAdapter|The adapter]]
does not call [[app/services/llm/prompt_cache.rb#Llm#PromptCache|Sway PromptCache]].
The guarded harness repeats the same synthetic prompt for each of the three
choices and reports both calls' token/cache fields, actual models and upstreams.
Absent reporting, zero reported cache tokens and a changing Auto route are
distinct outcomes. Two observations do not establish a stable cache threshold.

The same run reported the following usage for identical summary
prompts. Every pair retained the model and upstream recorded in the schema
observations, and the live spy verified that Sway PromptCache was not called.

| Requested choice | Input tokens, first/repeat | Output tokens, first/repeat | Cached input tokens, first/repeat |
| --- | --- | --- | --- |
| Deepseek Pro Latest | 2921/2921 | 864/810 | 0/2920 |
| Deepseek Flash Latest | 3691/3691 | 1838/2339 | 0/3562 |
| OpenRouter Auto | 3000/3000 | 760/749 | 0/2999 |

The reported hits establish cache use on these sampled routes. They do not
establish a minimum cacheable prefix: one prompt size and two calls per choice
cannot measure a threshold. The report therefore records no supported numeric
threshold. In particular, Auto may select a different model or upstream for
another prompt; its observed cache hit is not a general Auto caching guarantee.

### OpenRouter Decisions API transport for System One models

System One decision models evaluate structured classifications using OpenRouter's Decisions API endpoint rather than chat completions. The transport packages state, questions, and privacy constraints into a single non-chat request.

OpenRouter's specialized decision models (including ScaleDown Classify Latest, Jev Latest, Perplexity Decider Latest, and Perplexity Decider Flash Latest) evaluate candidates directly through `POST /api/alpha/decisions`. Because these models specialize in fast calibrated probability distribution over closed answer sets, they do not accept `/api/v1/chat/completions` payloads with conversational message arrays and JSON Schema format descriptors.

`[[app/services/llm/open_router_adapter.rb#Llm#OpenRouterAdapter|OpenRouterAdapter#generate_decisions]]` dispatches decision requests through a dedicated Faraday connection mounting [[lib/sway/faraday_stack.rb]] retry middleware and `X-OpenRouter-Metadata: enabled` headers. The request body enforces privacy via `provider: { data_collection: "deny" }` while transmitting state and typed questions:

```json
{
  "model": "scaledown/classify-1",
  "state": { "attachment": { "title": "Letter" } },
  "questions": {
    "is_testimony": {
      "type": "choice",
      "instructions": "Is this public hearing testimony?",
      "criteria": { "testimony": "...", "not_testimony": "..." }
    }
  },
  "provider": { "data_collection": "deny" }
}
```

Attribution verification on decisions responses accepts serving upstream identification from either `openrouter_metadata` endpoints or top-level `provider` or `provider_name` attributes. The adapter validates that `answers` contains an entry for every question key, confirming that choice questions return non-blank strings, finite probability hashes between 0.0 and 1.0, and selections conforming to question criteria when specified. Optional choice confidence and noul questions require finite numeric probabilities between 0.0 and 1.0, while score questions require finite numerics or non-blank strings. Custom base URLs resolve `/alpha/decisions` across URLs with or without a `/v1` suffix. Upstream failures and HTTP status errors map through error classification into [[app/services/llm/transport_error.rb#Llm#TransportError]].

### ScaleDown entity extraction through constrained decoding

ScaleDown's extraction model extracts target entities through constrained decoding rather than JSON Schema response formats. Field descriptions pass inside provider options on a standard chat completion.

The extraction model `scaledown/extract` (registered as ScaleDown Extract Latest) performs plain-English entity extraction across unstructured document text. Unlike general-purpose models that advertise structured outputs in catalog metadata, the model guides decoding using entity descriptions supplied in `provider.options.scaledown.entities`.

`[[app/services/llm/open_router_adapter.rb#Llm#OpenRouterAdapter|OpenRouterAdapter#generate_entity_extraction]]` validates that model and content are non-blank strings before constructing chat requests with user text content, `max_tokens`, and the configured entities hash while omitting `response_format`. The returned `choices[0].message.content` payload parses into a Hash of extracted entities. Upstream verification enforces standard metadata attribution, while token exhaustion or non-JSON payloads raise [[app/services/llm/schema_error.rb#Llm#SchemaError]].

## Whose words a stored summary records

A summary a person wrote is never published over, and the field that records the model's words keeps recording the model's words after an operator edits the draft.


The two are separate fields for that reason, and every example that touches them
makes them disagree, because a fixture where they move together cannot catch the
defect. An edit is stamped with the moment it landed rather than with new
authorship, which is why an exact comparison of a stored draft takes that one
key out and asserts it separately: the value is a timestamp, and everything else
about the entry still has to match exactly so an unexpected extra key is caught.

## Settings live in the database

LLM tuning — provider, model, limits — is stored in `AdminSetting` rows and
edited at `admin/llm_settings`, not in environment variables or config files.

The reasoning is deployment-shaped. A knob that needs changing in response to
model behaviour should not require a Kamal deploy onto a single Pi. The
opposite rule applies to anything that is a secret or that the application
cannot start without; those go through `Sway::Settings` and `EnvSecret`
instead, as [[reference/settings-and-secrets#Settings groups]] records.

### The settings route is a singleton

The admin settings page addresses one standing [[app/models/admin_setting.rb#AdminSetting]] record, so its singleton route has no row id and exposes show, update, refresh_models, add_model, and remove_model.

This keeps settings access tied to the one application-wide configuration row rather than suggesting that operators can choose among per-row settings records, while allowing collection actions to refresh cached OpenRouter models and manage the offered model list.

### UI selection and activation of OpenRouter models

Operators select OpenRouter models through searchable comboboxes on `/admin/llm_settings` and the Bill Creator summary tab, with conditional reasoning effort controls.

[[app/models/admin_setting.rb#AdminSetting|The shared settings allowlist]] offers the twelve baseline models alongside customizable offered models populated through [[app/services/llm/open_router_models_service.rb#Llm#OpenRouterModelsService|Llm::OpenRouterModelsService]]. Both standing model fields and all Bill Creator run-start branches consume that same list via searchable comboboxes, retaining model-only submissions while allowing reasoning effort selection (`low`, `medium`, `high`, or `default`) whenever a selected model supports reasoning. The route contract and dynamic routing architecture are owned by [[llm-summaries#Planned OpenRouter model choices]].

### A stored model that is no longer offered

A model name can come off the allowed list while a settings row still holds it, and the dropdown sends the stored name anyway — last, marked, and not selectable.

Leaving it out would show a blank selector for a model that is really running,
which reads as "nothing is configured" rather than as "this is configured to
something retired". Keeping it unselectable stops it being chosen again while
still saying what is in force.

### A refused save names the field that moved

A save that would write over a value another writer has already changed is refused, and the refusal names the column rather than reporting a generic conflict.

The two surfaces carry different sentences. A person is looking at the page the refusal redirects to, so theirs names the stored value and the way back to it inside the page; a script receives the column and the request that returns the current row. Neither asks for a browser refresh, which no surface in this project does.

### The browser settings test uses only offered models

The LLM settings browser selects from the server's offered model list rather than inventing an invalid value.

[[app/models/admin_setting.rb#AdminSetting#SUPPORTED_MODELS]] is the selector's allowlist. Invalid submitted values are covered by request tests, where a caller can send a payload the browser controls cannot produce.

### The source-text cap is read on every call

`BillSummaryPromptBuilder.max_source_chars` reads the setting on every call rather than holding the value in a constant, so one example can lower it through `with_app_config(:llm, llm_max_source_chars: ...)`.

## Per-locale legislative body context

Every bill summarization prompt carries instructions explaining the legislative body that produced it. Sway formerly embedded descriptions of all three supported legislatures into every prompt; it now renders only the bill's own context.

Sway previously described Baltimore City Council, the Maryland General Assembly, and the United States Congress in every prompt. A municipal bill in Baltimore was sent to the model with paragraphs explaining federal statutory citations and Maryland General Assembly 90-day sessions. Sway now scopes this text to the bill's own jurisdiction.

### Reading the bill's jurisdiction

`BillSummaryPromptBuilder#jurisdictional_context` resolves the bill's `sway_locale` and retrieves the chamber label and legislative makeup.

The chamber label and procedural makeup are separated by design:
- **Chamber Label**: Declared in code via `SwayLocale::JurisdictionRulesRegistry` (`City Council`, `General Assembly`, `Congress`). The database never overrides the registry's naming.
- **Legislative Body Makeup**: Stored in the `llm_bill_summarization_instructions` table (`legislative_body_makeup` column) keyed by `sway_locale_id`. The seeded text describes procedural rules, sponsorship rules, veto overrides, and citation forms without repeating the chamber label.

The prompt builder fetches the chamber label from the registry and prepends it to the makeup text:

```markdown
## Jurisdictional context

* **%{chamber_label}.** %{makeup}

When summarizing, name the jurisdiction explicitly so readers understand...
```

### Graceful degradation and compacting

Summarization prompts are constructed across multiple environments, including live pipeline runs, background jobs, test suites, and admin catalog previews.

If `bill.sway_locale` is nil, if the locale is undeclared in `JurisdictionRulesRegistry`, or if the `llm_bill_summarization_instruction` record or its `legislative_body_makeup` is missing or blank:

1. `BillSummaryPromptBuilder#jurisdictional_context` logs a structured warning via `SwayLogging.warn("bill_summary_prompt.missing_jurisdictional_context", ...)`.
2. The method returns `nil` rather than raising an exception.
3. `#system_prompt` joins sections via `[header, jurisdictional_context, output_contract].compact.join("\n\n")`. When jurisdictional context is nil, the section is omitted without producing extraneous blank lines.

This guarantee ensures that a newly provisioned locale or an unsaved `Bill.new` placeholder safely renders a well-formed prompt while alerting operators through logs.

### Per-locale worked examples

Summarization instructions provide an exemplar JSON output tailored to the specific jurisdiction rather than a single shared municipal ordinance.

Sway previously presented a hypothetical Baltimore City Council ordinance amending Title 14 of the Baltimore City Code to every language model call across all three jurisdictions. That caused municipal citation conventions to be sent as the exemplar for Maryland General Assembly state bills and United States Congress federal legislation.

To avoid citation leakage across jurisdictions, `BillSummaryPromptBuilder#output_contract_worked_example` resolves its exemplar from `bill.sway_locale&.llm_bill_summarization_instruction&.worked_example`:

- **Baltimore**: Exemplar references Baltimore City Council ordinance `CB 23-0312` amending Title 14 of the Baltimore City Code with penalties payable to the Baltimore City General Fund and enactment via mayoral signature.
- **Maryland**: Exemplar references Maryland General Assembly bill `HB 452` amending Environment Article Section 6-801 of the Annotated Code of Maryland with regulatory compliance certified to the Maryland Department of the Environment and enactment via gubernatorial signature.
- **Congress**: Exemplar references United States Congress bill `H.R. 2030` amending Title 42 of the United States Code with enforcement under the Lead-Based Paint Poisoning Prevention Act and enactment via presidential signature.

When `bill.sway_locale` is nil or the instruction record lacks a worked example, `#output_contract_worked_example` returns `nil`. Because `#output_contract` compacts its sections before joining, the `## Worked example` block is omitted cleanly without orphan headers or blank lines.

### Security boundaries: immutable legislative makeup and locale-authoritative news sources

System prompt text forms a strict security boundary, so legislative body descriptions remain immutable in code while news media sources are defined in declarative locale YAML.

The two fields stored in `llm_bill_summarization_instructions` have distinct security properties:

- `legislative_body_makeup` interpolates directly into the privileged `system_prompt` (`BillSummaryPromptBuilder#jurisdictional_context`). Exposing it to admin web forms introduces a prompt injection vector where an attacker or untrusted edit could alter system instructions, weaken civic neutrality, or attempt prompt escape. In addition, changes to this text invalidate prompt prefix caching across model calls.
- `news_media_website_urls` is an idempotently synchronized compatibility projection populated authoritatively from locale YAML (`config/sway_locales/*.yml`) by `SwayLocale::DocumentReader`. Candidate articles are placed strictly in `user_message` within `<NEWS-ARTICLES-BOUNDARY-...>` fences and sanitized via `renderable_news_url?`. Locale YAML ownership ensures trusted news sources are version-controlled and protected against unvalidated database mutation.

## Output is validated, not trusted

Generated text passes through `Llm::SchemaValidator` and
`Llm::ResponseNormalizer` before anything is stored, and
`SummaryCitationValidator` checks that a summary's claims point at sections
that actually exist in the bill.

An unreviewed summary is also marked as such in the UI rather than presented as
editorial copy. The prompt builders — `BillSummaryPromptBuilder`,
`BillPositionsPromptBuilder`, `BillCategoryPromptBuilder` — wrap upstream text
in `Llm::UntrustedTextBlock`, because bill text and hearing testimony are
attacker-influenced input arriving from third parties.

### Independent inputs for summaries and positions

[[app/jobs/generate_bill_summary_job.rb#GenerateBillSummaryJob|The job]] checks each call's inputs independently, because a testimony-only bill can support positions without supporting a summary.

The summary prompt uses diff markdown or extracted bill text; the provisioning
row's mirrored diff artifact is not a substitute for text the prompt renders.
Positions use testimony. A shared source-text gate would refuse useful positions,
while removing the summary gate would buy a summary with no bill text. The
in-job check also protects inline pipeline execution that bypasses the enqueue
service. A skipped or resumed summary call produces no new citation verdict or
category response. With neither input nor an earlier summary, the row settles
failed rather than displaying a completed result that does not exist. Fixtures
expecting a summary call therefore provide actual extracted text, rather than
only the mirrored diff artifact.

### Preserving the summary when positions fail

The positions region absorbs failures after the summary is committed, because restarting the entire job would purchase the summary again and hide a useful result behind a failed status.

Prompt construction, inference and serialization share that region in
[[app/jobs/generate_bill_summary_job.rb#GenerateBillSummaryJob|the job]]. Its broad
rescue covers malformed testimony and invalid serialized bytes as well as model
errors. Reloading the row discards an unsaved corrupt payload before completion
can try to save it again. Existing operator-edited position drafts survive a
failure or an unattempted positions call; only a successful replacement writes
new drafts. A missing input on this run does not prove an earlier audited draft
is wrong. The stored error claims a valid summary only when one is actually
present. Completed rows can carry either a positions failure or an evidence-change
discard reason; other failures cannot relabel their committed outcome.

### Multi-chunk positions generation and deduplication

The job queries partitioned testimony chunks sequentially, merging, deduplicating, and grounding positions across chunks before persistence.

When [[app/services/bill_positions_prompt_builder.rb#BillPositionsPromptBuilder]] partitions testimony across multiple chunked payloads, [[app/jobs/generate_bill_summary_job.rb#GenerateBillSummaryJob]] iterates over `#prompt_payloads` and invokes `#generate_bill_positions` on the adapter for each payload. Returned draft organization positions and news testimonies are accumulated across chunks. News testimonies are deduplicated by `[bill_news_article_id, text_version_id]`, keeping the first-seen entry to prevent duplicate drafts when responses echo news items. Accumulated organization positions are passed to [[app/services/news_org_position_grounding_service.rb#NewsOrgPositionGroundingService]], which enforces grounding against evidence snapshots, validates spokesperson authority, and deduplicates entries by canonical organization name, preserving earlier chunk occurrences on collisions. The grounded positions are capped at [[app/services/bill_positions_prompt_builder.rb#BillPositionsPromptBuilder#MAX_DRAFT_POSITIONS]] before persisting to `provisioning.draft_org_positions`. If any chunk fails, the job's positions-region error handler absorbs the failure, preserving previously committed drafts.

### Bounded errors preserve the operator instruction

[[app/jobs/generate_bill_summary_job.rb#GenerateBillSummaryJob|The job]] bounds stored error text so a large adapter message cannot inflate the database row or admin props.

A testimony-only run whose positions call fails must name that failure rather
than claim positions were generated. The reason's budget is derived from the
template's fixed text, with exactly one placeholder, so changes to the wording
cannot silently consume the instruction after the reason. Tests preserve room
for a useful adapter message, not merely a positive remainder. Truncation marks
the shortened reason and preserves the following sentence; a trailing full stop
is removed at the join to avoid doubled punctuation. Evidence-change wording
fits both its standalone error and its embedded reason slot. Other prefixed
errors are bounded after composition, rather than using a manually counted prefix.

### Failure logging preserves the committed outcome

Failure settlement re-reads the locked row before changing its error and status, because an in-memory generating state can outlive a concurrent completion.

[[app/jobs/generate_bill_summary_job.rb#GenerateBillSummaryJob|The job]] records
failures even outside a pipeline run, where a stage logger cannot report them.
Transport failures retain the retryable wrapper and schema failures retain the
discarded wrapper; their activity entries distinguish the operator's next action.
Failure settlement and activity-log writes rescue their own errors so a busy
database cannot replace the model error that controls retries. A failure arriving
after a terminal outcome is logged without relabeling the settled row. A rolled-back
paste hand-off leaves its run reclaimable rather than inventing a successful settle.

### Operator regeneration instructions in user prompts

Per-run operator instructions for summary regenerations are placed strictly inside user message text rather than privileged system prompt templates.

[[app/services/bill_summary_prompt_builder.rb#BillSummaryPromptBuilder#operator_instructions_section]] appends non-blank instructions under a distinct operator guidance section in the user message. Isolating operator instructions outside the system prompt preserves prompt prefix caching and prevents per-run requests from overriding factual grounding, neutrality rules, or structured JSON schema requirements. The model receives operator guidance as steering emphasis only and cannot treat it as factual evidence contradicting legislative source text.

### Cited local news reporting and domain-restricted web search

Sway enhances bill summaries with reporting from local newsrooms covering the bill's jurisdiction. Web search is restricted to explicit local domains and validated with a two-fold citation check before recording audit verdicts.

Retrieved articles are fenced inside untrusted text blocks and citations are checked against persisted results.

#### Seeded newsrooms and domain filtering

Each `SwayLocale` stores trusted local news media website URLs in its `LlmBillSummarizationInstruction` record (`news_media_website_urls` column). `Llm::AllowedDomain.from_url` converts these URLs into canonical search domains:
- Only HTTPS URLs are accepted; HTTP and invalid URIs are dropped.
- The `www.` prefix is stripped so root domains and subdomains match consistently.
- Localhost, IP addresses, and single-label hosts (e.g. `localhost`) are refused.
- To prevent prompt and parameter bloat, the allowed domain set is capped at 64 entries (logging a warning if an operator supplies more).

Source lists originate authoritatively in locale YAML documents (`config/sway_locales/*.yml`) read by `SwayLocale::DocumentReader`, while database `LlmBillSummarizationInstruction` rows serve as an idempotently synchronized compatibility projection. Seed routines and runtime access synchronize database rows directly from validated locale YAML declarations, preventing out-of-band drift.

#### Pre-summarization search and article persistence

Automatic news discovery is decoupled from pipeline runs, single-bill summary jobs, and batch submissions. Discovery runs only on explicit administrator request.

`GenerateBillSummaryJob` and `SummaryBatchSubmission` no longer trigger news retrieval. Summarization draws strictly from official legislative text and existing approved evidence, avoiding uncontrolled web queries, unexpected latency, and provider leakage during automated pipeline runs. The design rationale for decoupling discovery from pipeline execution is documented in [[news-implicit]].

Domain-scoped web queries execute through [[app/services/brave_search/client.rb#BraveSearch#Client]], which partitions allowed publisher domains across query batches to satisfy upstream limits of 400 characters and 50 words per request. The client normalizes search results into candidate dictionaries with headline, source URL, publication timestamp, outlet name, and bounded cited text, deduplicating articles by canonical URL across batches before returning them to callers.

[[app/services/bill_news_article_fetch_service.rb#BillNewsArticleFetchService]] requires a persisted bill and a Sway administrator. It records a discovery receipt and queries [[app/services/brave_search/client.rb#BraveSearch#Client]] using a search query built from the bill identifier, cleaned title, and locale name. If the Brave Search API key is unconfigured, discovery immediately records an `unsupported` receipt without dispatching network requests. Rescued retrieval exceptions scrub API keys using `BraveSearch::Client.redact_api_key`, log structured failure details, report to Sentry (`Sentry.capture_exception`), and record bounded receipt diagnostics. Matched candidates are attached as unapproved bill associations. The source and matching requirements are owned by [[news-source-configuration]]. Matching evaluates all configured path prefixes for each trusted host, rejects robots-disallowed paths before network requests, and schedules background text retrieval via `NewsArticleTextFetchJob`.

News article discovery is decoupled from `Llm::RouteResolver`. `BillNewsArticleFetchService` queries the Brave Search API directly via `BraveSearch::Client` regardless of whether summary routing targets Claude, OpenRouter, or llama.cpp. Receipt records stamp provider as `brave_search` and model as `web_search`, while summary generation routes proceed independently.

[[news-admin-ui#Integration into the Bill Creator summary tab]] details the administrative discovery and review interface. [[news-text#Bounded generic extraction]] documents the bounded text acquisition pipeline, including paywall and challenge filtering.

#### Robots policy enforcement and path authorization

Sway evaluates publisher directives strictly before issuing HTTP requests for article text. Crawler rules conform to RFC 9309 and reject unauthorized paths with zero outbound article requests.

The robots policy engine in [[app/services/news_article_robots_policy.rb#NewsArticleRobotsPolicy]] fetches and evaluates `/robots.txt` before any article retrieval begins. Acquisition operates fail-closed: unrecognized HTML, login redirects, subscription walls, or network failures at the robots endpoint refuse authorization rather than assuming permissive access. Responses without explicit allow policies fail visibly in test and production environments rather than masking missing permissions.

Path evaluation normalizes both literal UTF-8 sequences and percent-encoded path segments before matching against Disallow and Allow directives. When multiple crawler groups are present, empty Disallow lines maintain RFC 9309 group boundaries, preventing rules from bleeding across user-agent groups or importing wildcard allowances. Denied paths abort retrieval immediately, guaranteeing that prohibited URLs produce zero article download requests.

#### Restricted preview and challenge screen exclusion

Paywall previews, subscription gates, and CAPTCHA challenge pages are classified as unusable prior to text or metadata acceptance. Restricted screens never enrich article metadata or supply synthesis evidence.

Article text acquisition in [[app/services/news_article_text_fetch_service.rb#NewsArticleTextFetchService]] inspects response bodies for access restrictions before admitting content to synthesis evidence. Paywall indicators—including schema.org microdata with `isAccessibleForFree: false`, subscription paywall classes, account login forms, and Cloudflare or custom CAPTCHA challenge screens—fail usability classification.

When an article page is classified as restricted, the text version is recorded as failed or paywalled, and the system discards any extracted preview text. Furthermore, restricted responses are barred from enriching article metadata, preventing login screen titles or boilerplate copyright notices from overwriting author and publication dates. Approved title and URL references remain available to readers as textless related links, while administrators retain the ability to supply verified article text through manual entry.

#### Authoritative attribution for opinion commentary

Published news commentary preserves distinct identities for article authors, editorial boards, and publishing outlets. Generated opinion testimony never overrides authoritative attribution or invents names for uncredited writers.

When an approved news article represents an op-ed or editorial, [[app/services/news_article_testimony_service.rb#NewsArticleTestimonyService]] derives attributed commentary for civic perspective. Attribution maintains separation across three distinct identities: individual journalists or columnists (`author_name`), editorial boards (`organization_name`), and the publishing newsroom (`source_name`).

The service enforces attribution integrity by treating the article record's established metadata as the authoritative source of truth. Language model output cannot replace verified author names with speculative alternatives. For unsigned or institutional editorials, the system attributes commentary to the publisher or editorial board without fabricating individual bylines. Commentary generated from articles lacking author attribution leaves individual author fields nil rather than synthesizing fictitious names.

#### Prompt isolation and the no-paywall rule

[[app/services/bill_summary_prompt_builder.rb#BillSummaryPromptBuilder]] includes approved usable article text in the user message. [[news-summary]] owns snapshot isolation and prompt boundaries:
- Enclosed within `<NEWS-ARTICLES-BOUNDARY-xxxxxxxx>` tags.
- Bounded to `MAX_NEWS_ARTICLES = 5` and `MAX_NEWS_SECTION_CHARS = 10_000` (dropping entire rows when the character budget is reached).
- The prompt instructs the model to cite news coverage only from this allowed list, to write citations as in-prose markdown links in `summary_markdown` using the outlet name as link text, and to emit matching URLs in the optional `cited_news_urls` array (`config/schemas/bill_summary.json`).
- The style guidance explicitly includes: `"Do NOT label any news outlet as paywalled."` (ensuring seeded paywalled outlets like The Baltimore Banner are cited naturally without meta-commentary).

#### Two-fold citation validation and tri-state audit verdict

`SummaryCitationValidator.verdict_attrs(bill:, payload:)` evaluates both section citations and news citations:
1. **Two-fold Extraction**: Extracts structured URLs from `payload["cited_news_urls"]` and in-prose links / plain URLs from `payload["summary_markdown"]` (stripping trailing punctuation without capturing parentheses).
2. **Ground Truth Comparison**: Compares all extracted URLs against `bill.bill_llm_provisioning.news_articles`.
3. **Tri-State Verdict**:
   - *No claim made* (key absent and no prose URLs): `{news_urls_valid: nil, invalid_news_urls: nil}`
   - *Valid claim* (all URLs exist in allowed list and prose links <= 5): `{news_urls_valid: true, invalid_news_urls: []}`
   - *Invalid claim* (any cited URL unlisted, or prose links > 5): `{news_urls_valid: false, invalid_news_urls: [<unlisted URLs>]}`
4. **Audit Seam**: All three summary persistence surfaces (`GenerateBillSummaryJob`, `PasteSummaryService`, and `SummaryBatchResultPersister`) write these attributes to `bill_llm_provisionings`. Invalidation flags the audit column without blocking summary publication.

A valid news verdict establishes URL membership, while semantic support is governed by [[app/services/news_summary_manifest_validator.rb#NewsSummaryManifestValidator]] and [[app/services/news_claim_grounding_service.rb#NewsClaimGroundingService]]. The manifest validator enforces strict agreement between in-prose links and structured `source_uses`, rejecting invalid or unapproved sources before LLM generation. The grounding service assesses whether cited claims are factually supported by approved article excerpts within the captured snapshot.

#### Publication gating across generated and manual summaries

Summary publication requires strict citation validation and semantic claim grounding across both automated generations and manual editorial entries. Any invalid news source use halts publication.

Sway gates publication through [[app/services/news_claim_grounding_service.rb#NewsClaimGroundingService]] and [[app/services/manual_news_summary_publication_service.rb#ManualNewsSummaryPublicationService]]. Publication validation applies uniformly to LLM-generated summaries, batch ingestion, manual editorial revisions, and draft restorations.

The validation pipeline enforces two non-negotiable criteria: deterministic source authorization and semantic support. Every cited URL must correspond to an approved `BillNewsArticle` in the active evidence snapshot. If a summary contains even a single invalid or unapproved news source use alongside valid ones, the submission is rejected in its entirety rather than silently sanitized. Furthermore, semantic claim grounding verifies that statements citing news coverage are substantiated by the approved article text. Upon validation failure, the system preserves the last valid public summary and records audit diagnostics, preventing corrupted or ungrounded drafts from reaching public reader interfaces.

#### Decision on reader-facing news article credits: in-prose links over dedicated credit block

Reader components render in-prose citations, approved related links, and published commentary across web and mobile layouts. The workflow is fully integrated from administrative discovery to reader display.

Sway's civic engagement role requires explaining legislation and its supporting and opposing arguments. Cited journalism supplies reporting and context alongside Sway's own summarization without making Sway a news publisher. Declarative locale configuration in [[config/sway_locales]] owns trusted source lists and maps both direct bill coverage and surrounding-issue coverage to bills in that locale. Shared services consume that configuration without locale-specific classes or slug-based branching; congress-congress-united_states is the sole permitted locale-specific exception.

Article retrieval is an explicit administrator action. Ordinary pipeline runs do not fetch or assign news articles by default. Requested results attach to the bill as unapproved articles, and only administrator-approved articles become eligible for inclusion in a subsequent Sway summary. Automatic discovery has been excised from pipeline runs as described in [[news-implicit]].

Article text is retrieved where available, with administrator-supplied relevant text as the fallback when retrieval fails. An approved article with only a title and URL can appear as a related link, but cannot supply summary claims or testimony until text is added. The required claim and citation guarantees are defined by [[news-article-evidence#Grounding decisions]].

Op-eds and editorials belong in attributed testimony, with text establishing whose position is represented and the actual argument. An administrator can also establish whether the article supports or opposes the bill. That classification does not replace the text needed to summarize its argument. Published opinion remains distinguishable from submitted hearing testimony.

The news architecture separates article evidence from the [[partner-article-engagement#Partner article engagement#Data model and join relationship|partner engagement relationship]]. The [[news-article-evidence#News article evidence contract|evidence contract]] owns association approval, immutable text and snapshot fields, grounding outcomes, manual publication compatibility and changes after publication. The [[news-source-configuration#News source configuration contract|source configuration contract]] owns locale source declarations and evidence for matching articles to bills.

Readers access approved article links outside summary and testimony on both web and mobile bill surfaces, including Bill of the Month. Both clients render attributed published opinion with bounded query scaling; [[news-gate#Why opinion commentary is gated separately from hearing testimony]] explains how opinion commentary is isolated from hearing testimony and published upon validated summary generation. The web Bill Creator owns retrieval and review controls; public payloads exclude unapproved candidates and private source text.

## Where the style rules for generated copy live

The voice and tone section of [[app/services/bill_summary_prompt_builder.rb#BillSummaryPromptBuilder#output_contract_voice_and_tone]] is the reference for how generated prose reads. The installed journalism skills and `with-bellawatt-voice` are authoring aids read while prompt text is written and never sent directly to a model.

Rules from `newsroom-style`, `ai-writing-detox`, and `with-bellawatt-voice` sit inside [[app/services/bill_summary_prompt_builder.rb#BillSummaryPromptBuilder#output_contract_voice_and_tone]] as hand-typed instructions: the inverted pyramid with a 35-word cap on the lead, Strunk & White's economy of expression (omitting needless words, active voice and positive form, concrete specifics over corporate or bureaucratic jargon, one thought per sentence, reason before conclusion, varied sentence rhythm, and a strict ban on em dashes and horizontal rules), AP style conventions (whole numbers spelled out through nine, "more than" in place of "over", "fewer" for countable items, "percent" in place of "%", month abbreviations, restrictive "that" versus nonrestrictive "which", and "said" attribution), and a list of banned filler words and AI tells. Two copies of one standard can drift apart, so one of them is the reference, and the prompt is that one. A prompt edit is checked against the skills; a change in a skill is not on its own grounds for a prompt edit.

The same holds for all three pipelines — bill summaries, organization positions
drawn from testimony, and testimony attachment classification — and costs
nothing at runtime. `source-verification` bears on attributing a stance to a
person or an organization, where a sending domain is provenance rather than
identity. `data-journalism` bears on vote counts and agreement scores rather
than on summarising prose, so it has no place in these three.

The AP rules and the banned-word list stay in the prompt while nothing checks
the model's output against them. `SummaryCitationValidator` checks that cited
section keys name real parsed sections, and nothing comparable exists for
voice, so a summary opening "This landmark bill is very important" clears every
gate. Trimming the prompt follows a checker that reports those rules redundant,
and no such checker exists. The operator-triggered premium path for a single
bill is the cheapest place for one, because it runs on one bill on
demand rather than on every bill in a pipeline run.

### Organization position summaries carry no voice section

`BillPositionsPromptBuilder` states no voice or tone standard, and
`Testimony::ClassificationPromptBuilder` states none either. The asymmetry with
bill summaries is accepted rather than unnoticed.

The visible cost is one screen carrying a bill summary written to AP style
beside a position summary written to no stated standard. The cost on the other
side is runtime prompt text added without a measured need, on a shared prefix
whose token count already has consequences that
[[llm-summaries#Batch summarisation#Why the saving is the batch discount alone]]
records. A measurement of the gap between the two summaries is what would change
that decision.

### Which standard governs reading level and filler

Reading level follows the `simple-english` standard. Filler words follow the
prompt's own banned-word list, the slice of `ai-writing-detox` already typed
into the prompt. The two govern different things.

Where the two would name different words for one sentence, the plain-language
rule stands, because it is the reader-facing one: a summary is read by a member
of the public deciding how to vote. The editorial variant planned for the
operator-triggered premium path carries a brief — stakes, who is affected,
civic consequence, a stronger lead — and repeats none of the style rules the
default prompt already ships, so the rules stay in one place rather than two.

### Bill diff interpretation and before-and-after guidance

`BillSummaryPromptBuilder` instructs the model how to interpret legislative unified diff blocks embedded in the prompt:
- Lines prefixed with `-` are text stricken or removed from standing law.
- Lines prefixed with `+` are text added or inserted into standing law.
- Unmarked lines are surrounding statutory context.

When source text is supplied without a diff (such as unamended bills or statutes without existing codified counterparts), the prompt explicitly directs the model to summarize only the enacted text provided and strictly forbids speculating about what the prior law stated.

In the output contract, `summary_markdown` is structured in Markdown sections for the general public, while detailed before-and-after statutory explanations are directed to `full_breakdown_markdown`. Where a diff is present, `full_breakdown_markdown` walks through each amended section, explaining what the law required before and after the amendment and identifying who is affected by the change.

## Public summary content and source grounding

Public summaries are structured in substantive Markdown sections with linked citations grounded in official legislative sources or news reporting.

[[app/services/summary_citation_validator.rb#SummaryCitationValidator|The shared validator]]
gives generated summaries and operator pastes the same citation
verdict. An omitted section-citation key leaves the verdict unset, because no
validation is not evidence of valid citations. A skipped summary call likewise
cannot fabricate a verdict for a response it never bought.

In the output contract, `summary_markdown` replaces the prior two-to-four-sentence ceiling with structured Markdown sections (such as `### Purpose`, `### Key Provisions`, `### Who Is Affected`, `### Timing and Implementation` where supported by source text). Simple bills with narrow scope do not need artificial padding. Detailed statutory before-and-after section analysis belongs in `full_breakdown_markdown`.

Claims in `summary_markdown` may be grounded with Markdown hyperlinks citing either the official bill link provided in `bill_metadata` (`bill.link`) or verified newsroom reporting from `cited_news_urls`. `SummaryCitationValidator.news_verdict_attrs` checks supplied official bill links separately from news articles, without requiring newsroom provisioning. Acceptance of a stored link does not establish bill identity: the remaining official-address repairs are prerequisites to complete source-grounding verification.

Citation matching preserves query values exactly without altering parameter values. Removing a slash from an entire URL changes a Legistar record parameter, so string-level trailing slash stripping cannot establish equivalence; component-aware comparison limits path normalization strictly to path segments while requiring exact query and fragment equality. Generic search URLs are filtered so only bill-specific sources are presented in prompt metadata or accepted during citation validation, leaving the official link absent when no bill-specific address exists.

## Runs are marked and reclaimable

A summary generation in flight is tracked by `SummaryRunMarker`, armed by
`SummaryRunArmDecision` and released by `SummaryRunRelease`, with
`ReclaimAbandonedSummaryRunsJob` cleaning up after a process that died
mid-generation.

The structure mirrors the pipeline's own run bookkeeping for the same reason:
on a single machine, a crashed container is an ordinary event, and a marker
with no reclaim path would leave a bill permanently stuck looking busy.

### Why the reclaim judgement lives on the row

`BillLlmProvisioning#reclaimable?` is published on the model and sent out on the provisioning prop, rather than staying inside the service method a Generate click reaches.

The judgement began inside `GenerateBillSummaryService#reclaim_abandoned_run!`,
which runs in exactly one place: a Generate or Regenerate click. Every control
posting to those is disabled while the row is `pending` or `generating`, so the
recovery was reachable only by an operator who did not need it. A row a dead
worker left `generating` on a bill with no prior summary had no exit at all —
the panel renders a disabled button for that status with no condition on it, and
the stale header carrying the other Regenerate button cannot appear either,
because `#stale?` needs `llm_generated_at` and a row that never produced a
summary has none. The only ways out were a full pipeline run over the whole
locale, or a Rails console. A guarantee that a row never strands cannot rest on
a client choosing to offer a button.

A nil `updated_at` is deliberately not reclaimable. Every row this application
writes has one, so a nil means the row was built outside the ordinary path, and
"unknown" must not read as "free" — the same rule `SummaryRunArmDecision`
applies to the same question.

### One lock shared by the job and the persist guard

`SummaryRunLock.settle_under_lock` is `GenerateBillSummaryJob`'s former private `#settle_under_lock`, moved out so `SummaryRunPersistGuard` can take the same atomic read-check-write without a second copy of the locking and rescue logic.

`with_lock` on SQLite takes no row lock — Arel's SQLite visitor drops the
locking clause, so the serialization actually comes from
`default_transaction_mode: IMMEDIATE` (`config/database.yml`): the write
lock is taken at `BEGIN`, so a competing writer blocks at its own `BEGIN`
and cannot commit between the re-read and the write inside the block. Every
gate in `GenerateBillSummaryJob` that re-checks committed state before
writing goes through this one method, and so does the persist guard below —
two callers sharing one lock rather than two copies that could drift the
first time either was edited.

A row deleted mid-flight raises `RecordNotFound` from `lock!`; there is
nothing left to settle, so the method logs
`generate_bill_summary.provisioning_vanished` and returns `nil` rather than
letting the exception replace whatever error the caller was already
handling.

### The persist guard is extracted so a batch ingest can call it directly

`SummaryRunPersistGuard.call` is `GenerateBillSummaryJob`'s former private
`#persist_unless_superseded!`, moved out whole so an ingest can reach it
without entering the job.

It is the compare-and-swap deciding whether a bought summary or positions
answer may land on a `BillLlmProvisioning` row, or must yield to an operator's
paste or to testimony that moved underneath it.

The job's own top-level gate, `STALE_AFTER`, refuses to run any enqueue
sitting in the queue for over an hour — the right call for the synchronous
path, where a stale enqueue means the worker that owned it died. A batch
result is different: Claude's Message Batches API can legitimately take up
to twenty-four hours, so an ingest reading that result back is not the dead
run `STALE_AFTER` exists to catch, and must never reach it. Three routes
could get a batch answer onto the row without tripping that gate: reuse the
job (not actually available — its body is "build a prompt, call the model,
persist the answer," and an ingest already holds the answer, so routing it
back through the job would re-buy work already paid for), write the row
directly (silently loses the paste-supersede and evidence-digest
protection `#persist_unless_superseded!` provides), or extract the guard so
both the job and a future ingest can call it without the job's staleness
gate in the way. The third is what `SummaryRunPersistGuard` is.

The extraction moves the DECISION only. The former method also reacted to
its own `:superseded` verdict by calling `#stand_down_mid_run` before
returning — a job-only method the guard cannot reach once it is a
standalone class. `SummaryRunPersistGuard.call` returns `:superseded`
without acting on it, and both call sites in `GenerateBillSummaryJob#perform`
now call `#stand_down_mid_run` themselves immediately after receiving that
verdict, in the same place and order the old code ran it — so the job's own
behavior on a `:superseded` result is unchanged. A future batch ingest reacts
to `:superseded` in whatever way fits an asynchronous write instead.

`#superseded_by_operator_paste?`, the job's former one-line wrapper around
`SummaryRunMarker.operator_paste?(provisioning.summary_run_id)`, did not
move to a shared helper: every remaining caller, in both the job and the
guard, calls `SummaryRunMarker` directly, which is already the single
source of truth for that check.

A fourth thing can happen that the three named outcomes have no word for: the
row is deleted while the call is in flight. `SummaryRunLock.settle_under_lock`
swallows that `RecordNotFound` and answers `nil`. `nil` used to reach the
`else` branch and come out as `:persisted` — a vanished row borrowing the
word for success, harmless at the two-minute scale of a synchronous call but
unusable once the caller is a batch ingest that already paid for the answer
it is reporting on (a batch ingest's read arrives up to a day later, so the
window a row can vanish in is not two minutes but a day). A deleted row now has
its own outcome, `:vanished`, so the guard's four possible answers are all
named and none of them borrows another's meaning.

`GenerateBillSummaryJob`'s two call sites treat `:vanished` the way the job
already treats a row that vanished before it was ever armed
(`#arm_row_unless_owned!`, `#clear_stale_run_state_unless_superseded!`): log
that the paid call's answer has nowhere to land, and return `NOT_RUN` without
touching the row again — there is nothing left to settle, and the pipeline's
`resume` picks the bill up again rather than the run reporting success for
nothing. The not-yet-written batch ingest gets no such helper; it needs to
say out loud, in its own terms, that a result it already paid for did not
land.

### One armer for both the synchronous run and the batch

`SummaryRunArm.call` is `GenerateBillSummaryJob`'s former private arm, moved out whole so `SummaryBatchSubmission` can claim a row the same way rather than through a second copy of the rules.

The arm is not one decision but four things done together under one lock:
taking the decision from `SummaryRunArmDecision`, walking the row through
`enqueue!` and `start_generating!`, stamping `updated_at` so the abandonment
clock restarts, and writing this run's claim over `summary_run_id`. A second
implementation that got any one of those wrong — most easily the clock, which
`update_columns` does not touch and no state transition writes from
`generating` — would leave a batch-owned row looking abandoned to the very
sweep the batch columns exist to hold off.

What differs between the two callers is small enough to be a parameter. The
synchronous job identifies itself with ActiveJob's `job_id`; the batch
submission has no such thing per bill and supplies
[[llm-summaries#Batch summarisation#What identity arms a batch-submitted row]]
instead. The batch also has two more columns to write, `summary_batch_id` and
`summary_batch_expires_at`, and it cannot write them with the claim: neither
value exists until the batch has been bought, which happens after the row is
claimed. They are stamped in a second statement once the submit returns, under
the same row lock, and that statement declines if a paste took the row while
the submit was in flight. The gap between claim and stamp is covered by the
`updated_at` the claim refreshes, which holds the reclaim sweep off the row for
its quiet-time threshold. The arm's `extra_columns` parameter is what such a
merge would use and no caller passes it.

What stayed in the job is its logging: the decline message, the reclaim
warning, and the Activity Log entry for a paste that already settled. Those
read as one job's account of what happened to one bill, and the batch path
reports its own equivalents in its own words. The reclaim warning is reached
through a block the arm yields under the lock, so the job still logs against
committed state.

## Stand-downs are reported, not swallowed

`#perform` returns `NOT_RUN`, `SETTLED`, or `STOOD_DOWN`, and `RunLegislationPipelineJob` reads that value rather than treating every non-raising return as success.

`STOOD_DOWN` covers the runs that deliberately spent nothing: an operator-paste
marker on the row, or a bill with neither source text nor testimony to draw a
positions call from. `SETTLED` still covers a stand-down that bought a
positions call before finding no summary text — that call was real money
spent, so it earns "succeeded" the same as an ordinary run. The distinction
exists because a green pipeline run used to be indistinguishable from one that
changed nothing: an operator-pasted row showed a completed stage and no error,
with nothing on screen connecting the click to the fact that it bought
nothing. `RunLegislationPipelineJob` maps `STOOD_DOWN` to the
`skipped` stage status — the same status an artifact-present skip uses, so it
still counts as done on resume rather than being retried into standing down
again — but visibly not `succeeded`.

### The pipeline tab warns before it stands down

The earlier fix stopped the pipeline tab from *reporting* a stand-down as success, but said nothing before the operator clicked Run. The standing notice described here closes that gap.

`BillCreatorPipelineLlm` reads the same `paste_owns_summary_run` flag the summary tab already renders (`LlmSummaryInFlightNotice`, via `LlmSummaryCompletedView`) and shows a standing notice, `PipelineOperatorPasteNotice`, above the pipeline controls whenever it is true.

The notice is a small local component rather than a reuse of `LlmSummaryInFlightNotice`: that component gates on `generation_status` being `pending`/`generating`, because it is about a run currently overwriting a draft. The pipeline-tab notice has to show whenever a summary is operator-owned, independent of run status — that is a different condition, not a variant of the same one. That same constraint also rules out adding a second regenerate control here: the notice only names Regenerate, on the Summary tab, as the control that overrides a pasted summary.

### The activity log names the stand-down and what to do about it

`GenerateBillSummaryJob` writes a `PipelineActivityLogEntry` for each of the two reasons it declines to call: an operator's paste already owns the row, or the bill has no source text to summarize.

The two get separate event types, `summary_stood_down_for_paste` and `summary_skipped_no_source_text`, because they call for different operator actions and naming the wrong one sends someone to the wrong control. A paste stand-down names Regenerate, on the summary tab, as the control that clears the paste marker — Run Pipeline never does, so pointing there would send the operator in a loop. A no-source-text skip instead names the pipeline's extract-text and fetch-hearings stages, since Regenerate does nothing without source text to draw from.

Both are `info` severity, the same as `paste_summary_accepted`: the job doing exactly what the row's state calls for is not an error, even though the operator-facing symptom — no summary bought — looks the same as one from the Activity Log's row list alone.

The paste entry is written at every site that discovers the marker: the top-of-`#perform` gate, the two callers of `#stand_down_mid_run`, `#finish_deferred_paste!`'s four callers, and the arm's `:paste_already_settled` decline. The no-source-text entry is written where `#settle_nothing_to_generate` and `#settle_no_source_text` actually mark the row failed, downstream of their own `#finish_deferred_paste!` check — a paste discovered on the way to failing the row is the paste cause, not this one.

## A run that fails before it starts still settles

An error raised while the provisioning row is still `pending` moves it to `failed`, on the same `mark_failed` event that moves a `generating` row.

The failure settlement used to act only on a `generating` row, because that was
the only state the event accepted. A run can reach the paid region with the row
still `pending` — `start_generating!` is called only when the row can take that
transition, and a concurrent run may have moved it in between — and an error
there left the row `pending` with an error message written beside a status
saying it was still queued. The service's own guard refuses a fresh run against
a `pending` row, so the bill could not be summarised again at all, which is the
same dead end already fixed for the stale gate.

The `generating` path is unchanged, retries included: a rescued attempt still
stamps the row `failed` before ActiveJob schedules the next one, and the next
one re-arms it through `enqueue`, which accepts a `failed` row.

## A local server that is not running is said once

In development the job asks the configured llama.cpp server for its model list before arming a row, and declines the run when there is no answer.

A pipeline run summarises every bill in it one after another, so a local server
that is not running turned into hundreds of connection failures, each retried,
each writing three lines — 1,701 lines from one cause, with every real error in
the log buried under them. The probe costs one local request against a server on
the same machine, and it is asked per bill rather than remembered, so a server
that comes back up is used on the next bill rather than after a restart.

The warning stands for a minute, so a fan-out reports the condition once instead
of once per bill. The run returns the same "nothing was produced" answer it uses
for every other declined run, which the pipeline already records as such.

The probe is development-only. Production talks to the Claude API, where there is
no local server to be down and a probe would be a second paid round trip; test
never reaches a real endpoint at all, and a probe there would be a network call
the suite does not need.

## Talking to the Anthropic SDK

Three small modules hold everything the synchronous adapter and the batch service both have to get right about the Anthropic SDK: how a client is built, how its exceptions are translated, and how a reply is read.

Each of the three exists because two callers need identical behaviour, and the
same reasoning that produced `Llm::ClaudeRequestParams` applies to them: a
duplicated rescue chain drifts the first time either copy is edited, and a
divergence between the two paths is silent — both keep working, they just stop
being comparable.

### Why the two budgets sit with the client

`Llm::ClaudeConnection` owns a two-retry budget and a 120-second deadline, and hands back a fresh client rather than a memoised one.

The deadline matches llama.cpp's default so the two providers fail on the same
clock. It reaches a message request through `request_options:` rather than the
client, because `Messages#create` overrides a non-default client-level timeout;
the client-level value is only the transport default for other endpoints. The
retry budget is the SDK's own — one initial call plus two retries per job
attempt — and the worst-case wall clock it implies is asserted in
`claude_adapter_spec.rb` rather than restated here.

Memoisation stays with each caller, because the two have different lifetimes: an
adapter instance is one job run, while the batch service is a singleton that
outlives any one submission.

### Why the rescue chain has an order

`Llm::ClaudeErrorTranslation` rescues timeout, connection, rate-limit, authentication and bad-request before the generic `APIStatusError` they descend from.

Ruby matches rescue clauses top to bottom, so the generic clause placed first
would swallow all five and reduce every failure to a status code. Rate-limit and
authentication translate to fixed strings carrying no upstream text, since
neither adds anything a status code does not and both can echo request detail
into a log. The other three carry at most 200 characters of the upstream
message, which keeps a log line readable and mirrors the summary job's own cap.

`Anthropic::Errors::BadRequestError` (400) is the one status code where the
upstream message is the entire diagnosis rather than noise: the fixed
`"claude transport: 400 bad_request_error"` form once discarded a Batches API
validation message naming the exact field and pattern that failed, leaving
nothing to act on. Its `rescue` clause has to sit above the generic
`APIStatusError` clause it subclasses, same as the other four, or it never
matches.

An exception that is not an Anthropic error passes through untouched. That is
deliberate: a Sway bug disguised as a transport failure would be retried instead
of fixed.

### Why a truncated reply and an empty one are different classes

`Llm::ClaudeMessageText` raises `Llm::SchemaError` when a reply stopped at the token cap, and `Llm::TransportError` when it arrives blank.

Truncation is deterministic — the same prompt against the same cap truncates
again — so a retry re-pays for a guaranteed failure, and the class that gets
discarded rather than retried is the honest one. A blank body is the opposite
case: it can be passing network noise, so it stays retryable. That choice buys
resilience at the cost of occasionally paying for a retry a misbehaving model
will fail again.

### Why the reply is searched for a text block

The JSON is not reliably in the first content block, so the extractor scans for the first block whose type is text rather than reading position zero.

Extended thinking prepends a thinking block, and structured outputs can route the
JSON into a `tool_use` block instead. Neither type answers `#text`,
so reaching for the first block raises `NoMethodError` — which is not an
Anthropic error and so escapes the rescue chain entirely. The error raised when
no text block exists names the block types that were actually present, because an
earlier version blamed `tool_use` unconditionally and sent triage of the
thinking-block failure the wrong way.

## Batch summarisation

A full pipeline run summarises a locale's bills in one pass, so the same work is worth buying at half price. A batch path proves out alongside the synchronous one rather than replacing it.

Claude's Message Batches API returns the same completions for half the token
price, and a full run is the ideal shape for it: every bill is independent and
nobody is waiting on any one result. What stops it being a straight swap is
time. A batch may take up to twenty-four hours, while `RunLegislationPipelineJob`
holds a four-hour concurrency lock and `ReclaimAbandonedPipelineRunsJob`
force-fails a run that has been quiet for four hours. Submitting a batch from
the stage before those thresholds are reconciled would have runs killed while
they were working correctly, so the API was proved first against real dumped
prompts, leaving the pipeline untouched.

### Why the request builder was extracted

`Llm::ClaudeRequestParams` holds the system block, the cache-control decision and the structured-output arguments that `Llm::ClaudeAdapter` previously built inline.

The batch path has to send the same bytes as the synchronous path or the
comparison proves nothing — a summary generated from a subtly different prompt
is not evidence about the batch API at all. Two hand-written builders would
drift the first time either was edited. One shared builder makes the two paths
the same object graph rather than two things that resemble each other, which is
what the parity claim rests on.

### Why a service rather than a third adapter

`Llm::ClaudeBatchService` sits outside the adapter allowlist `Llm::Client.build` selects from.

The adapter contract is five methods that take a prompt and return a validated
hash, synchronously. A batch cannot honour it: submission returns an identifier
rather than an answer, and the answer arrives later, possibly after the process
that asked for it has been replaced. Presenting that as a third adapter would
mean either blocking for hours inside a method that claims to be synchronous, or
returning something that is not a summary. The shape differs, so the seam does
too.

### Not every bill earns a batch item

A batch has to settle the stand-down decisions before it submits, because a submitted item is paid for whether or not its answer is kept.

The synchronous path discovers each reason not to spend one bill at a time, on
the way to the call it then does not make: an operator's paste already owns the
row, there is no source text to summarise, there is no testimony to draw
positions from. All three live inside the same method that would otherwise have
spent, described in [[llm-summaries#Stand-downs are reported, not swallowed]].

Batching inverts that. Every one of those decisions falls due up front, at
accumulate time, and separately per answer type — the summary call and the
positions call are gated on different evidence, so a bill can legitimately earn
one item and not the other. A batch built by walking bills and emitting two
items each would buy, at half price, work the synchronous path is careful not
to buy at all.

### One reader decides whether a bill earns a batch item

`SummaryItemEligibility` answers, per bill and per answer type, whether a summary item and whether a positions item should be built — without making an adapter call.

The stand-down evidence has to match what the synchronous job would have found, or a batch would buy work the synchronous path refuses, or skip work it would have bought — and the two paths would stop being comparable. Rather than have the accumulate step re-derive "no source text" or "no testimony" from scratch, `SummaryItemEligibility` reads through the same objects `GenerateBillSummaryJob` already reads: `SummaryRunMarker.operator_paste?` for the paste stand-down, `BillSummaryPromptBuilder#source_present?` for the summary gate, and `BillLlmProvisioning#testimony_present?` for the positions gate. `GenerateBillSummaryJob` was changed to call the same object at its own four decision points (the top-of-run paste stand-down, the summary-call gate, the positions-call gate under the row lock, and the resumed-run settle), so there is exactly one reader rather than two that could drift.

An operator's paste is reported by `#operator_paste?` and deliberately not folded into `#summary?` or `#positions?`. A paste stands the whole run down rather than withdrawing one answer type, and the synchronous job already stands down on it in two places the evidence gates never reach — at the top of the run, before the row is armed, and again in `SummaryRunPersistGuard` when a paste lands while a paid answer is in hand. Folding the marker into the evidence gates would route a mid-run paste around both, skipping the paid call but settling the row as though the evidence had been missing all along, with no paste recorded in the Activity Log. Keeping the three predicates independent leaves each one answering about one piece of evidence, and leaves the batch submitter to compose them the way the job does.

`GenerateBillSummaryService#runnable?` reads the same two evidence predicates and stays outside this object on purpose. It asks whether an enqueue is worth making at all, which is one question over both answer types rather than one per type, and it asks it before the run exists — so it also counts testimony being supplied by that very call, which is not yet on the row for `#positions?` to see. Routing it through `SummaryItemEligibility` would make it answer a narrower question than the one it is there to answer.

### Why no job waits on a batch

Submission and ingestion are separate: one job submits and returns, and a scheduled poller ingests the results later. Nothing blocks on a batch.

Two reasons, and only the second survives every possible measurement. The lock
`RunLegislationPipelineJob` holds expires after four hours, so a batch that
legitimately runs longer has the lock vanish underneath it and the reclaim sweep
force-fails a run that is working correctly — a failure that is silent and reads
as a pipeline bug. That argument depends on batches sometimes being slow. The
second does not: production is a single Raspberry Pi running one job container, so
a blocking run occupies the only worker for the whole wait, however short. Two
proving batches each ended in about two minutes, which is evidence that slow
batches may be rare, but it does not weaken the container argument at all.

Polling is not a preference. Message Batches cannot push completion to a
listener: the gem ships a complete webhook subsystem, which makes one look
available, but every event type it defines belongs to the Managed Agents beta and
`BatchCreateParams` accepts no callback field. Verified against the installed gem
rather than the documentation, which has already been wrong about this API twice.

The consequence is that a run cannot report complete with summaries outstanding.
It holds an explicit waiting state that the orphan and abandoned sweeps exempt,
bounded by the batch's own expiry so exempting it does not remove the safety net
outright.

### Why the waiting state loops back to summarizing

`awaiting_summary_batch` sits between `summarizing` and `summarizing` again: `await_summary_batch` leaves the former, `resume_summary_batch` returns to it, so ingest calls the same `complete_summarize!` a synchronous run already used.

Landing back on :running instead would need ingest to re-derive which stage a
resumed run was in, or a second completion event that duplicates
`complete_summarize!`'s stage-sync and current_stage bookkeeping. Reusing the
existing state after the wait keeps the resumed run indistinguishable, from
that point on, from one that summarized synchronously.

It is declared a stage state — added to `PHASE_52_STAGE_STATES`, mapped to
the same `"summarize"` DAG name as `summarizing` — so `current_stage`, the
active-run concurrency guard, and `force_fail`'s reachable-from set all
already cover it without a separate carve-out; the only new logic is the
exemption on the abandoned sweep described above.

A batch row whose `expires_at` is nil is treated as already expired rather
than as no ceiling. Nothing observed submits a batch without recording its
expiry, so a nil here means the write was skipped or lost, and the fail-safe
direction is to let the reclaim sweep close the run rather than have it wait
forever on a ceiling that was never recorded.

### Why resume draws the same line as abandonment

`RunLegislationPipelineJob#normalize_for_resume` found `awaiting_summary_batch` in the same generic per-stage status list it reopens as stuck, so a resume would reopen a run whose batch was still paying to run.

`normalize_for_resume`'s stuck-stage sweep exists for a worker that died
mid-stage: it puts the run back in `:running` and clears the stuck stage's
rows so the resumed attempt redoes the work. `awaiting_summary_batch` was
added to `PHASE_52_STAGE_STATES` — the very list that sweep reads generically
— so once anything submits a batch, a resume clicked while it is still
in flight matches the same "stuck" test and reopens the run. The resumed
attempt then resubmits the same bills to a paid API while the original batch
is still outstanding, and its results arrive later into a run that has moved
on.

`LegislationPipelineRun#summary_batch_awaited?` is the one predicate for "one
of this run's batches can still return results" — `abandoned?` and
`normalize_for_resume` both call it rather than each restating the expiry
check, so the two cannot drift apart the way two independent copies of the
same rule eventually do. A resume of a run for which it is true is left
untouched: the run keeps its batches and its `awaiting_summary_batch`
status, and the job returns without walking any stage. It logs an `info`
activity-log entry rather than raising, on the same precedent as
[[llm-summaries#Stand-downs are reported, not swallowed]] — this is the job
declining to act, not a failure, and the entry is what tells an operator who
clicked Resume why nothing happened. A resume of a run whose batch has
already expired (or that never recorded an expiry) finds `summary_batch_awaited?`
false and normalizes exactly as it did before this predicate existed.

### Why the per-bill exemption needs its own ceiling

`BillLlmProvisioning#summary_batch_awaited?` mirrors `LegislationPipelineRun#summary_batch_awaited?` one level down: `reclaimable?` and the `reclaimable_candidates` scope both call it, so the two cannot drift as separate copies would.

A row a batch has claimed keeps its existing `pending`/`generating`
`generation_status` — there is no separate per-bill waiting status, because
`GenerateBillSummaryService`'s reclaim path already treats those two statuses
as "a run owns this row" and a third status would need every caller of
`pending?`/`generating?` re-audited for a case they do not expect. What marks
a row as batch-owned instead is `summary_batch_expires_at`: present and in the
future, the row is left alone however long it has been quiet; past it, or
absent, `ReclaimAbandonedSummaryRunsJob` treats the row exactly as it did
before batching existed. A nil `summary_batch_expires_at` is read as already
expired rather than as no ceiling, on the same reasoning the run-level
predicate uses — nothing that submits a batch skips recording its expiry, so a
nil here means the write was skipped or lost, and the fail-safe direction is
to let the sweep close the row rather than have it wait forever on a ceiling
never recorded.

`reclaimable_candidates` is the sweep's SQL-side first pass, so it has to stay
an exact logical negation of `reclaimable?` — including the nil-expiry case —
or a row the scope cannot see is a row the sweep never even locks to find out
`reclaimable?` would have released it. `spec/models/bill_llm_provisioning_spec.rb`
pins that the two agree over every combination of status, quiet time, and
batch expiry, the same shape `legislation_pipeline_run_spec.rb` uses to pin
`abandoned_candidates` against `abandoned?`.

A `summary_batch_id` column carries which batch a row belongs to, for
observability only — nothing in the reclaim path reads it. It is deliberately
not unique: many rows share one batch, and the submission step splits a run's
summarisation work across more than one batch, so a run's rows are not all
carrying the same `summary_batch_id` either.

### Why results are collected rather than raised

Results arrive as a value per request, each carrying either a parsed summary or an error, and only a failure of the whole fetch raises.

The synchronous adapter raises because one call has one outcome. A batch has
many, and a single malformed response among two hundred is a poor reason to
discard the other hundred and ninety-nine, which have already been paid for.
Errors therefore travel as values, and the caller decides which are worth
resubmitting.

### Two traps in the gem

Both cost more to rediscover than to record, and neither is visible from the published API documentation.

The Ruby SDK names the results method `results_streaming`, and has no `results`
method at all, although the published examples for other languages use that
name. Code written from those examples raises `NoMethodError` where results are
read, which is after the money has been spent.

For a failed request the useful fields sit two levels down, at
`result.error.error.type` and `result.error.error.message`. The intervening
`result.error.type` is always the literal envelope value, so a reader that stops
one level short reports the same uninformative string for every failure.

A third trap sits in the request body rather than the response: the Batches
API requires each `custom_id` to match `^[a-zA-Z0-9_-]{1,64}$`, and this
constraint appears nowhere in the gem's signatures. A `custom_id` built by
naively joining identifiers (a bill's external id and an answer type, say,
with `/`) passes every local check and is rejected at submission with a 400
that fails the *entire* batch — after the whole payload, covering every bill
in the run, has already been built. `Llm::BatchCustomId.build` is the fix:
every `custom_id` is built through it rather than by interpolation, so an
illegal character is caught and normalized before any request is
constructed. Its `.valid?` predicate lets `Llm::ClaudeBatchService.submit`
reject a bad batch locally, naming every offending id, before spending a
network round trip on one that the API would have refused anyway. A
sanitized id that would still exceed 64 characters is truncated with a hash
suffix rather than a plain truncation, because two long ids sharing a prefix
must not collide into the same `custom_id` once shortened.

### What a batch can report while it runs

An operator watching a full run wants to know how far along it is. A batch answers that only partly, and the shape of the answer decides what the admin UI can honestly show.

The four outcome counts — succeeded, errored, canceled and expired — are
documented as zero until processing of the entire batch has ended. Successes
cannot be watched accumulating. Only `processing`, the number still in flight,
carries no such caveat, so the one derivable figure is the submitted total minus
that number.

Whether `processing` decrements while the batch runs, or holds at the total
until the end, is stated nowhere in the API documentation. If it moves, a
percentage is available; if it does not, there is no progress signal at all.
The proving harness logs the counts on every poll for that reason, so the
question is settled by measurement rather than by assumption.

No estimate of remaining time exists. `expires_at` is the twenty-four hour
deadline rather than a prediction, and throughput is uneven enough that
extrapolating from elapsed time would mislead most in the first minutes, which
is when someone would look.

### Sizing the results-read timeout

`Llm::ClaudeConnection::BATCH_RESULTS_TIMEOUT_SECONDS` gives `ClaudeBatchService.results` its own per-request deadline instead of inheriting the 120 seconds sized for one synchronous completion.

A three-item proving batch finishes in about two minutes, well inside 120
seconds, but a full-locale batch carries up to two answers — summary and
positions — for every bill in the run, and reading that many results is a
different operation from waiting on one reply. Reusing the synchronous number
would size the read against the wrong workload, which is why it stays where
[[llm-summaries#LLM bill summaries#Talking to the Anthropic SDK#Why the two budgets sit with the client]]
put it and this is a third, separate figure rather than a change to either.

The figure is arithmetic rather than a guess, and the measured and assumed
parts are kept distinct. A real positions answer for bill 25-0064 measured
5,110 bytes — the largest of any real answer
sampled, ahead of the development database's stored `llm_summary` (max 401
bytes across 35 rows), `llm_full_breakdown` (max 3,243 bytes across 2 rows)
and `draft_org_positions` (max 2,816 bytes across 35 rows) on
`bill_llm_provisionings`. The Baltimore locale carries 204 bills in the
development database; Maryland and Congress carry none yet, so Baltimore is
both the only measured locale size and the largest by definition.

A JSONL results line wraps that content in a `MessageBatchIndividualResponse`
envelope — id, model, role, stop reason, usage — that the gem's own model
class documents but no captured real batch supplies a size for. Encoding a
representative envelope around the 5,110-byte sample measures roughly 580
bytes of overhead, for a worst-case line of about 5,690 bytes; this envelope
figure is a constructed estimate, not a measurement of a real batch response.

204 bills × up to 2 answers × 5,690 bytes ≈ 2.27 MiB for one full run's
result set. Against an assumed floor of 10 KB/s — an order of magnitude
under ordinary broadband, chosen to absorb reconnects and slow parsing, and
not itself measured — that set takes about 227 seconds to read. Confirmed
against the installed gem's `PooledNetRequester#execute`, the deadline this
timeout produces is a single wall-clock point fixed for the whole attempt:
`calibrate_socket_timeout` recomputes the *remaining* budget against that
same fixed point after every chunk, rather than resetting a fresh window per
chunk, so the 227-second figure bounds the entire streamed read and is not
undermined by a response that arrives in a slow, steady trickle.

`BATCH_RESULTS_TIMEOUT_SECONDS` is set to 600 seconds, roughly 2.6× that
227-second figure. The extra margin beyond the arithmetic is deliberate
rather than padding for its own sake: nothing blocks on this call — the
result read runs from a scheduled poller, per
[[llm-summaries#LLM bill summaries#Batch summarisation#Why no job waits on a batch]]
— while a read that stops too early repeats the failure this issue exists to
close, so a wider margin costs nothing on one side and buys safety on the
other. 600 seconds is still a fraction of the twenty-four hours a batch is
allowed to take, and sits well clear of the synchronous adapter's untouched
120-second budget beside which it now runs rather than inside.

### Why the saving is the batch discount alone

Prompt caching was expected to stack on top of the 50% batch discount and does not, because Haiku declines to cache a prefix as short as this one.

Every request in a run shares the same summarisation instructions, which is
the shape prompt caching exists to reward, and the Message Batches API does
support caching — the two discounts stack, and hits inside a batch are
best-effort at a documented 30% to 98%. None of that reaches this workload.
The minimum cacheable prefix is a per-model figure: 1,024 tokens on Sonnet 5.5,
but 4,096 on Haiku 5.5. The shared prefix measures 2,141 tokens, and
production summarises full runs on Haiku.

A prefix under the floor is not cached and no error is raised, so the failure
is silent by design: every `cache_control` marker stays in place, reports
zeros, and explains nothing. An early proving run appeared to contradict this
by reporting 2,141 cache-creation tokens, because `sway:llm:prove_batch`
defaults to `claude-sonnet-5-5` — above whose floor the same prefix sits
comfortably. The measurement was real; it was of a model this path does not
use.

Growing the prefix past the floor to make it cacheable was considered and
dropped: the saving this path is built for is the batch discount, and chasing a
second one would mean padding a prompt to clear a threshold, which charges the
added tokens on every request whether or not the cache is ever hit.

### Why chunking is a progress decision, not a cost one

Splitting a run's work across several batches costs exactly what one batch costs, so the only thing it buys is something to show an operator.

The API reports nothing while a batch runs. Its per-request counts hold every
request in `processing` and every other bucket at zero "only once processing of
the entire batch ends", `processing_status` moves straight from `in_progress`
to `ended`, results stay behind a `results_url` that is null until then, and no
webhook or event stream exists for batches — polling is the only observation
mechanism, and every poll returns the same numbers until the last one. Requests
do finish incrementally server-side, which cancelling a batch reveals in its
partial results, but nothing exposes that short of ending the batch.

So a single batch leaves an operator with an elapsed timer and nothing else,
and several batches give a true "3 of 8 complete" at the same price. That is
the whole trade, and it is against complexity rather than against money.

One trap for a later reader: the example response body on the API reference for
retrieving a batch shows `in_progress` alongside non-zero `succeeded` and
`errored` counts, contradicting the prose on the same page. It is a schema
placeholder that fills every field with a sample value, not a behavioural
claim.

The schema shape follows from that decision. A run owns a
`pipeline_run_summary_batches` collection — one row per batch, carrying that
batch's own id, `submitted_at` and `expires_at` — rather than one such triple
of columns on the run row, which could only ever describe a single batch.
`summary_batch_awaited?` is correspondingly true while any one of those rows
can still return, and the nil-expiry reading is per row: a batch that recorded
no expiry counts as already expired and so holds nothing open, which leaves a
run owning only expired, expiry-less or no batches reclaimable exactly as it
was before batching existed. `abandoned_candidates` stays the exact logical
negation of `abandoned?` over that collection, the same obligation
[[llm-summaries#Batch summarisation#Why the per-bill exemption needs its own ceiling]]
carries one level down, and `legislation_pipeline_run_spec.rb` pins the two
against each other over every combination of live, expired, expiry-less and
absent batches.

### Submitting a run's summarisation as chunked batches

`SummaryBatchSubmission` accumulates a full run's summarisation work, chunks it, submits each chunk, records what was submitted, and returns. Nothing in it reads a result back.

The stage it replaces walked the run's bills one at a time, calling
`GenerateBillSummaryJob.perform_now` and waiting on Claude for each. The order
the batch path does things in is not arbitrary: every bill is asked for its
eligibility first, so no payload is built for work that would not be bought;
the items are then grouped and submitted; and only once a chunk's submit has
returned an id and an expiry is each of that chunk's rows armed. The arm cannot
come earlier, because the two columns that exempt a row from the abandoned
sweep are the batch's own answer, and it must not come later, because a row a
batch has already been paid for is a row a concurrent synchronous run could
otherwise claim and buy a second time.

A chunk that fails to submit fails the whole stage. Chunks already submitted
keep their `pipeline_run_summary_batches` rows and their armed provisioning
rows, so nothing paid for is forgotten even though the run itself ends failed;
what happens to those results is the ingest's problem rather than this step's.

The consecutive-failure budget the per-bill walk carried is given up here
deliberately: a chunk has one outcome for every bill in it, so a model that has
started refusing fails the stage on the first submit rather than on the fifth
bill, which is stricter than the budget was. What the budget protected against
moves to the ingest, where a
stage whose every ingested item errored fails.

### Which runs submit a batch at all

A run submits batches when it is an all-bills run and the configured provider is Claude. Everything else keeps the synchronous walk.

Two independent reasons narrow it that far. A single-bill run is one the
operator started from the summary tab and is waiting on, Regenerate summary
being the usual way in, and an answer that may arrive in twenty-four hours is
unusable there — so that path stays on `GenerateBillSummaryJob`, unchanged. And a
batch exists only on Claude's API: development and test run against a local
llama.cpp server, which has no batch endpoint, so a run configured for it has
nothing to submit to. Similarly, selecting an OpenRouter model routes summary
generation through OpenRouter, which does not participate in Anthropic Message
Batches; `SummaryBatchSubmission.for(run:)` inspects the route resolved by
`Llm::RouteResolver.resolve(purpose: :summary)` and returns `nil` unless the
route is Claude (`route&.claude?`).

Deciding these questions in one place, `.for`, means the orchestrator asks once
and gets either a submission object or nil, rather than carrying condition checks
of its own.

[[app/services/summary_batch_submission.rb#SummaryBatchSubmission|The submission]]
captures the selected Claude model at construction. Accumulation, outbound
items and the stored batch record retain that snapshot even if settings switch
to OpenRouter or the environment changes before submission. Direct construction
also refuses a non-Claude route; the inference provider cannot be checked once
and then replaced by a later settings read.

### Retaining the model for batch retries

Submitted batches record the selected model on the batch row so that retry processing preserves the model used at submission time rather than reading current settings.

When `SummaryBatchIngest` retries failures or settles batch items, it preserves the original Claude model from the batch record (`batch.model`) rather than picking up an OpenRouter model if the standing setting changed while the batch was in flight.


### What decides how many batches a run submits

`AdminSetting#summary_batch_chunk_size` gives the number of bills one batch carries, defaulting to twenty-five.

It is a column rather than a constant because the number is a progress-display
choice rather than a correctness one, and the shape of a locale's work changes
without the code changing — which is the project's standing rule for a knob
that must move without a deploy.

The unit is bills, not items, and that matters: a bill earns one or two items,
and keeping both of a bill's items inside one batch means one bill's answers
arrive together. Chunking by item count would split a bill across two batches
that can finish hours apart, leaving the ingest to hold half an answer with no
way to say how long it should wait for the other half.

### What a custom_id has to carry

Each item's `custom_id` is `bill__<bill id>__<answer type>`, built through `Llm::BatchCustomId.build`.

A result comes back carrying nothing but its `custom_id`, so the id is the only
route from an answer to the row it belongs on. Two facts are needed and no
more: which bill, and which of the two answer types, since a bill can have both
items in the same batch. The batch itself says which run, because
`pipeline_run_summary_batches` records that, so the run id would be redundant
weight inside a sixty-four character budget.

The bill's numeric id is used rather than its `external_id`. An external id is
operator-facing text of no fixed length or alphabet, so it would routinely need
`BatchCustomId`'s sanitisation and, past the length limit, its hash truncation —
at which point the id is no longer readable back apart. The numeric id is short,
fixed-alphabet and already the primary key the ingest looks the row up by.

### What identity arms a batch-submitted row

`SummaryRunMarker.batch_run_id` gives a batch-armed row the identity an ActiveJob `job_id` gives a synchronous one, derived from the batch id and the bill id.

The pipeline job has exactly one `job_id` and arms many rows, while
`summary_run_id` is uniquely indexed where it is not null — so its own job id
could arm one bill and would collide on the second. A per-row identity is
therefore required rather than preferred.

It is derived rather than random for the ingest's sake. The purchase receipt a
result has to be persisted under is that same identity, and deriving it from
the batch and the bill lets the ingest recompute it from what a result already
tells it, instead of the submit step storing a second copy of it somewhere for
the ingest to look up.

### Why a row is claimed before the batch is bought

Every row in a chunk is armed first, and only the rows that were successfully claimed have their items submitted. The batch identity is stamped on afterwards.

The synchronous path holds this order already: `GenerateBillSummaryJob` arms the
row and returns `NOT_RUN` if it cannot, and only then makes a paid adapter call.
Submitting first and arming afterwards inverts that. A bill whose row another
writer took — an operator's Regenerate summary is the reachable case, and that
button keeps working during a run — would have its items bought
anyway, and the loss would be discovered one line later with the money already
gone.

Claiming first turns that into an exclusion rather than a purchase: the
contended bill is left out of the chunk, earns `not_run` rather than
`awaiting_batch`, and a resume comes back for it. The cost is that a claim is
taken before the batch it names exists, which is what `batch_pending_id` is for
— an identity valid for the window between claiming and submitting, replaced by
`batch_run_id` once the batch has one.

Nothing releases a claim if the submit then fails. That is deliberate: such a
row has no `summary_batch_expires_at`, so it is not exempt from the abandoned
sweep, and the sweep reclaims it on the same terms as any other row whose writer
died. Adding a release path would duplicate a mechanism that already exists and
is already tested.

### Why the expiry is the server's answer

Every `pipeline_run_summary_batches` row records the `expires_at` the API returned with the batch, never a locally computed twenty-four hours.

That value is the ceiling on the run's whole exemption from the reclaim
sweeps, and on each of its rows' exemption one level down. A local computation
would be a guess at the server's clock, and a guess that ran short would have
the sweep force-fail a run whose batch was still legitimately alive; a guess
that ran long would hold a dead run open past the point where anything could
still arrive. Reading it back from the submit response makes the two ends agree
by construction.

### Why a submitted item is a verdict, not a silence

`awaiting_batch` is the fifth per-bill stage status, and the zero-succeeded check counts it alongside `succeeded`, `skipped` and `not_run`.

That check asks whether a stage produced any verdict that is not a failure, and
refuses to let a stage in which every bill failed report success. A bill whose
items are in a submitted batch has produced exactly such a verdict — the work
is bought and in flight — so leaving it out would have the check see nothing
but failures and abort the run on the spot, moments after paying for it.

`stage_already_succeeded?` deliberately does not count it. The status is
transient: the ingest rewrites each bill's entry to a terminal one when the
results land, so a bill still reading `awaiting_batch` when a resume comes past
is a bill whose batch expired without returning, and that bill genuinely needs
doing again.

### Why the batch path is off until it is switched on

`AdminSetting#summary_batch_enabled` gates the whole batch path and defaults to false, so a full run keeps walking bills synchronously until an operator turns batching on.

Everything the batch path needs has been proved against documentation and
against small batches of real prompts, but never against a production full run
of two hundred bills. The two are not the same evidence: chunk sizing, the
results-read timeout, the ingest's rebuilt identifier map and the retry bound
all only meet their real shape at that scale, and the first run to meet it
should be one somebody chose to make.

Without a switch the next production full run would go to batches by itself,
because the only other conditions — an all-bills run on the Claude provider —
are what an ordinary production run already is. The flag is a database column
rather than a constant for the project's standing reason: it has to move
without a deploy, and the operator turning it on wants to point it at one small
locale first.

### A purchase is sent exactly once

The batch-create call opts out of the SDK's retry budget. Every other call to the API keeps it.

The Anthropic client is built with two retries and attaches no idempotency key
unless one is configured, which this project does not. The SDK retries on a
timeout as well as on the retryable status codes, so a request the server
accepted and charged for, whose response was lost on the way back, is sent
again as a second batch. A multi-megabyte upload finishing near the client's
timeout is the realistic case, and only the last id returned reaches the
database, so the earlier batches run to completion unread.

Reading results and asking a batch's status are free and idempotent, so they
keep the budget. A failed submit already fails its stage with nothing recorded,
which costs one run's summarisation; a duplicated submit costs the same money
twice with nothing to notice it.

### Why an unknown custom_id is an error, not an exception

A result whose `custom_id` the rebuilt map does not hold becomes a result carrying an error, delivered alongside the rest, rather than a `KeyError` that abandons the whole set.

`Llm::ClaudeBatchService.results` was written for the proving rake task, which
holds in memory the exact items it submitted moments earlier and can never
present an identifier that does not resolve. Failing loudly there is right: an
unknown id would mean a bug in the task itself.

The ingest is the opposite case. Its map is rebuilt from the database hours
after submission, and it can legitimately have drifted — a bill deleted, a run
restarted, a row reassigned. Losing two hundred paid-for summaries because one
identifier no longer resolves is precisely the outcome the per-item result
design described in
[[llm-summaries#LLM bill summaries#Batch summarisation#Why results are collected rather than raised]]
exists to prevent, so the unresolved id joins the errors instead of replacing
the answers.

### A batch is read back exactly once

`ingested_at` on `pipeline_run_summary_batches` is the record that a batch's results have been read and settled, and `pending_ingest` is the set of rows that still need reading.

Two different questions are asked of a batch row and they have different
answers. `live?` asks whether a batch can still return anything, and it is what
exempts a run and its bill rows from the reclaim sweeps. `ingested?` asks
whether anybody has read it. An expired batch is not live and yet still needs
reading — it holds whatever results did come back, and the items that expired
are the clearest case for a retry — so a sweep keyed on liveness would skip
exactly the batches that most need attention.

The mark also makes the sweep idempotent, which matters because it runs every
five minutes against rows that are being written by an ingest that may still be
in flight. Reading a batch twice would persist the same answers twice, and the
second pass would land on rows the first already settled.

The identifier map is rebuilt from the provisioning rows that carry the batch's
id rather than from the prompts, because reading a result needs only the
validation schema for its answer type. Rebuilding the prompt would read source
files that may have changed since submission and would buy nothing: the answer
in hand was generated from the text as it stood then, and the guard that
decides whether it may still be written is the evidence digest rather than a
re-read of the source.

### Which runs the sweep can reach

The sweep reads every run parked in `awaiting_summary_batch`, and every run in a terminal status that still holds an un-ingested batch.

Two failures made the earlier scope too narrow, in opposite directions. Asking
for a pending batch as well as the status meant a run whose last batch was
stamped read, but whose bills were not all settled, fell out of the sweep
entirely, with nothing left that could move it to a terminal state. Asking for
the status alone meant a run that failed partway through submitting its chunks
was invisible, and every chunk already bought went unread for the whole
twenty-four hours.

A run still working through its stages sits outside both arms. Batch rows exist
from the moment the first chunk is submitted, which is before the run parks on
them, and a sweep reaching a run in that window would finalize it while its own
stage loop was still running.

### What identity a batch result writes as its receipt

A persisted batch answer writes `SummaryRunMarker.batch_run_id` into `summary_run_id` — the bare marker, where the claim taken at submission time carries the `run:` prefix.

The synchronous path draws the same distinction with the same two values: it
arms a row with `run_claim(job_id)` and, on persisting a paid answer, replaces
that with the bare `job_id`. The prefixed value means a run holds this row; the
bare value means this run already bought the body the row is carrying. Keeping
that distinction in the batch path is what lets a second pass over the same
batch tell an answer already written from one still owed, without consulting
anything outside the row.

### A failed item is retried once, as a batch

An item that comes back errored, canceled or expired is rebuilt and resubmitted as a new batch carrying `attempt: 2`; a second failure stands, and reaches the operator through the Activity Log.

The three outcomes are not the same situation. Expiry says nothing about the
request, only that the batch ran out of its twenty-four hours, and cancellation
says only that somebody stopped the batch — both are clear cases for asking
again. An error may be structural: a prompt over the model's limit, or a schema
the reply cannot satisfy, fails again for the same reason, and a resubmit costs
money whether or not it works. One attempt is the line that serves both without
paying twice for a failure that was never going to change.

The retry is a batch rather than a synchronous call because resubmitting
synchronously would put back the blocking call the whole phase exists to
remove — one bill's retry would occupy the Pi's only job container for the
length of a model call, at full price, inside a sweep that is meant to return
immediately.

The attempt count lives on the batch row rather than in a job's memory, so the
bound holds across processes and survives a worker being replaced mid-wait. A
retry batch's rows are already `generating` and already owned by this run, so
they are not armed again; what moves is the stamp naming which batch they are
waiting on.

Bills whose items succeeded are settled and their scores recomputed whatever
happens to the failures beside them. A bill with one half persisted and the
other exhausted settles completed carrying the failure in `generation_error`,
which is the shape the synchronous path already uses when a positions call
fails beside a valid summary.

### The read is recorded before the retry is bought

`mark_ingested!` runs before `retry_failures`, so a batch is recorded as read before any money is spent on the items that failed in it.

The two orders fail differently, and only one of the failures costs money. With
the purchase first, an interruption between the two leaves a bought retry and
an unstamped batch: the next tick re-reads the same results, computes the same
failures, finds the attempt count still on its first value, and buys the retry
a second time. A crash is not needed for this — a busy database on the stamp is
enough. With the stamp first, the same interruption leaves the failures
unretried and their rows for the reclaim sweep to release.

A bill left for the reclaim sweep is recoverable. A batch bought twice is not.

### A retry asks eligibility again before it buys

`retryable_answer?` re-asks whether an item is still wanted before rebuilding it for a retry, rather than trusting the decision made when the batch was submitted.

Up to twenty-four hours pass between the submit and the read, and the row can
move under the batch in that time. An operator can paste a summary. An earlier
attempt can already have persisted one. Testimony can arrive or be withdrawn.
Rebuilding an item from the failure alone would pay for an answer the persist
guard is certain to discard, which is the outcome the eligibility check exists
to prevent at submit time and had no equivalent on the retry.

A row a paste has taken over is never rebought, and never restamped onto the
retry batch, so the paste is what the guard still sees when the answers land.

### A bought batch is logged before it is recorded

The id of a retry batch is logged as soon as the submit returns, before the row that records it is written.

A submit is a purchase and the row naming it is a separate statement. If the
insert fails, the batch still exists and is still charged, and nothing in the
database points at it. The log line is then the only surviving record of its
id, which is what an operator needs to cancel it or read it by hand.

### What the operator sees while a batch is outstanding

The pipeline tab shows chunks ingested out of chunks submitted, the item counts each chunk brought back, and how long it has been since the first submission. It shows no estimate of when the run will finish.

Progress finer than a chunk does not exist to be shown. A batch holds every
per-item count at zero until it ends, so within a chunk there is nothing to
watch; chunking is what turns that into a real fraction, which is the whole
reason
[[llm-summaries#LLM bill summaries#Batch summarisation#Why chunking is a progress decision, not a cost one]]
chose it. An indicator implying finer resolution would be inventing a number
the API never gave it.

No completion estimate is shown either. `expires_at` is a hard ceiling rather
than a prediction, and throughput across a batch is uneven enough that
extrapolating from elapsed time misleads most in the first minutes — which is
exactly when somebody looks. Elapsed time and the deadline are facts and are
shown as facts.

The field reaches the client through the run's Jbuilder rather than an alba
resource, which is how every other run field travels, and so it is not covered
by the exact key-set request spec that pins the alba resources. `to_builder`
returns nil for a run with no batches, so nothing changes for a single-bill run
or for any run made before batching existed. The prop it rides on is already in
the partial-reload list the pipeline tab polls on, so no new prop key is needed
and the five-second poll already refreshes it.

Much of the narrative an operator needs is in the Activity Log rather than
here: the ingest writes the same per-bill entries the synchronous job writes,
so a stand-down, a provider error or an unreadable reply is described where
those are already read. The notice above the pipeline controls answers the one
question the log cannot — whether the run is waiting or stuck.

### Why a result carries the model that answered

`Llm::ClaudeBatchService::Result` carries the model named on the returned message, and that is what a persisted batch answer records as `llm_model`.

A request names whatever `AdminSetting#summarization_model` held when the batch
was built, which may be an alias rather than a concrete snapshot, and the
setting can be changed by an operator during the hours a batch is in flight.
Reading the setting again at persist time would stamp rows with a model that
never saw the prompt. The message says which model actually answered, so that
is the value worth keeping.

### Why the evidence digest is stamped at submit time

`bill_llm_provisionings.summary_batch_testimony_digest` records the testimony digest as it stood when a positions item was bought, and the ingest hands that value to `SummaryRunPersistGuard` hours later.

The guard's evidence check exists so positions generated from one body of
testimony are not written after that testimony has changed — the synchronous
path reads the digest immediately before the call and passes the same value to
the persist a few seconds later. A batch has no such moment to read from: by
the time the answer lands, the row's current digest describes testimony the
answer never saw, so comparing against it would compare a value with itself and
prove nothing.

Stamping at submit time is what preserves the check across the wait. Testimony
that changed while the batch ran now makes the stored digest differ from the
row's, the guard reports `evidence_withdrawn`, and the drafts the previous run
left stand rather than being replaced by positions drawn from evidence that has
since been withdrawn.

### One settle shared by the job and the ingest

`SummaryRunSettle.completed!` holds the settle that closes a bill's summary row, called by `GenerateBillSummaryJob` and by the batch ingest alike.

It settles only a row that is still `generating`, under the row lock, and it is
the one place that decides whether the interesting-score recompute is worth
enqueuing. Both of its keyword arguments carry a rule rather than a preference.
`clear_generation_error` is true only on the paths that settle a row without
buying anything — the re-entry gate and the supersede stand-downs — because a
path that did buy something has already written whatever error belongs on the
row. `recompute_score` is false wherever the caller can prove the run made no
paid call, so a stand-down does not enqueue work over a bill nothing changed on.

Copying it into the ingest would have put a second copy of both rules behind a
path that is exercised hours after the first, where a divergence would show up
as a bill that quietly never recomputed its score.

### One stage-result writer for the job and the ingest

`PipelineStageResult.record` writes one bill's verdict for one stage, and both the orchestrator and the batch ingest go through it.

The write is an atomic `json_set` merge rather than a read-modify-write,
because two writers can hold the same `pipeline_run_bills` row — which is now
the ordinary case rather than the unusual one, since an ingest running on a
schedule writes into rows a resumed run may also be walking. The `DAG_ORDER`
membership check guards path validity, not injection: the stage name is
interpolated into the JSON pointer, and only a name the pipeline knows may
reach it.

### One finalizer for the job and the ingest

`PipelineRunFinalizer.call` decides a run's terminal status, and the ingest calls it because the run it finishes may be finished hours after `RunLegislationPipelineJob` returned.

The distinction it draws — `succeeded` when nothing failed, `partial` when some
bills did — is read from each bill's `stage_results` rather than from the run's
own status column, because a bill can fail a later stage after succeeding an
earlier one. Leaving that decision inside the orchestrator would mean the batch
path either duplicated the rule or never applied it, and a run whose
summarisation half-failed would report unqualified success.

The optional `origin` is passed by the orchestrator and omitted by the ingest,
so the log line naming bills nothing ran for reads exactly as it did before the
extraction.

### What a batch that cannot be read back settles as

A read that fails against a batch still inside its expiry is left for the next tick; one that fails against an expired batch is settled as though every item it still owed had expired.

The two cases look identical at the point of failure — a transport error while
asking for results — and only the expiry separates a network fault worth
retrying from a batch whose results are gone for good. Leaving an expired batch
unread would hold its run in `awaiting_summary_batch` forever, since the sweep
only ever revisits batches that have not been read.

Every answer the batch carried settles, and what the row still owes decides
only how. An answer the row already holds settles as satisfied; one it still
lacks settles as a failure carrying the read's error. Deciding what to settle
at all from what the rows owed left a bill that owed nothing unsettled while
its batch was stamped read, so the bill's stage stayed `awaiting_batch` and the
run finalized reporting a success over work nothing had closed.

The distinction matters because the item map is a superset of what was bought:
it names both answer types for every row the batch stamped, whether or not both
were submitted. Treating all of them as failures would write a positions
failure onto a bill that never had testimony to form a position from.

### What settles a bill once its items are accounted for

A bill's row is settled when every item of its that this batch carried has landed or failed, and none of them is going out again on a retry.

Three outcomes follow from that. Any answer persisted settles the row completed
and records the stage succeeded, even beside a failure, because the answer is
bought and the bill is better off with half of it than with none. Nothing
persisted and everything failed settles the row failed, carrying the reason.
And a failure that is being retried settles nothing at all: the row stays
`generating` and its stage stays `awaiting_batch`, so the retry batch's own
ingest is what closes it — which is also what stops a resume walking past a
bill whose work is still outstanding.

"Nothing persisted" is asked of the row rather than of this batch. A retry
carries only the items that failed, so the batch answering it never sees the
summary an earlier attempt already wrote; deciding from its own results alone
would mark a bill failed while a valid, paid-for summary sat on its row. A row
already holding a summary or a set of draft positions settles completed with
the failure in `generation_error`, whichever batch wrote the half that landed.

A row a paste has taken over is not failed either. The write that would fail it
declines, and the stage is recorded succeeded, which is what a stand-down for a
paste records everywhere else. A row that moved to some other state entirely is
recorded `not_run`, so the run's own report counts it.

A row that vanished while its answer was in flight is the one case with nothing
to settle. Its stage is recorded `not_run` rather than left where it was, so
the run's own report counts it and a resume comes back for the bill if it
returns.

### Where the per-outcome counts come from

The succeeded count a batch row records is the number of answers that came back
usable; the errored, canceled and expired counts come from the API's own
per-item tally.

The two sources answer different questions and neither answers both. Only the
API distinguishes an item it rejected from one cancelled mid-flight from one
that ran out of time, so those three buckets have to come from it. But the API
counts as succeeded any request that returned a message, including one whose
JSON does not satisfy the schema it was asked for — and such an answer settles
its bill with a generation error. Reporting it as a success would put a number
on the operator's screen that contradicts the bill's own state, which is the
one thing the progress display exists not to do. An answer the API counted and
this application could not read is therefore counted with the failures.

An answer that arrived usable and was then declined still counts as a success:
a row an operator's paste owns, or one whose testimony changed while the batch
ran, stands the answer down without anything being wrong with the answer. That
stand-down is reported against the bill, where the reason for it lives, rather
than against the batch that produced a perfectly good reply.

### Token usage recording on direct and batch summarisation paths

Every completed model interaction on direct and batch paths records integer token counts so operations can aggregate spend across both mechanisms.

Structured usage logging runs at each interaction completion. For direct Anthropic calls in `Llm::ClaudeAdapter`, usage is recorded under the event `claude.usage.recorded` on `generate_structured`. For batch summarisation in `SummaryBatchIngest`, usage attached to each successful batch item result is logged under `claude.usage.recorded.batch` when the item is settled. Both events log identical keys (`model:`, `input_tokens:`, `output_tokens:`, `cache_creation_input_tokens:`, `cache_read_input_tokens:`) as bare integers, avoiding the key `token` which is filtered by sensitive key scrubbing. Failed calls and batch items with nil usage emit no usage event, preventing failed items from appearing as zero-cost requests.

Because both events match `grep 'claude.usage.recorded'`, an operator can compute total input tokens across a log file with:
```bash
grep 'claude.usage.recorded' log/production.log | grep -o ' input_tokens=[0-9]*' | cut -d= -f2 | awk '{s+=$1} END {print s+0}'
```
and output tokens by substituting `output_tokens` in place of `input_tokens`.
