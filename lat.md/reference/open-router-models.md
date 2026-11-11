---
lat:
  mode: reference
---

# OpenRouter models catalog

Specification and lookup contract for dynamic structured-output and decision OpenRouter models cached by `Llm::OpenRouterModelsService`.

- For architectural rationale on dynamic routing and Solid Cache selection, see [[llm-summaries#Planned OpenRouter model choices]].

## Service constants

Lookup table of endpoint URLs, cache configuration keys, TTL durations, and network timeouts.

| Constant | Value | Purpose |
| --- | --- | --- |
| `MODELS_ENDPOINT` | `"https://openrouter.ai/api/v1/models?supported_parameters=structured_outputs"` | Upstream OpenRouter models catalog endpoint filtered for structured output support |
| `DECISION_MODELS_ENDPOINT` | `"https://openrouter.ai/api/v1/models?output_modalities=decisions"` | Upstream OpenRouter models catalog endpoint filtered for System One decision support |
| `CACHE_KEY` | `"llm/openrouter/structured_output_models/v1"` | Solid Cache storage key for shared worker access |
| `DECISION_CACHE_KEY` | `"llm/openrouter/decision_models/v1"` | Solid Cache storage key for dynamic decision models |
| `CACHE_TTL` | `12.hours` | Expiration window for cached model catalog entries |
| `OPEN_TIMEOUT_SECONDS` | `5` | Faraday open timeout for network connection |
| `READ_TIMEOUT_SECONDS` | `10` | Faraday read timeout for catalog retrieval |
| `SLUG_PATTERN` | `%r{\A(?!.*\.\.)~?[a-zA-Z0-9][a-zA-Z0-9._-]*/[a-zA-Z0-9][a-zA-Z0-9._:-]*\z}` | Anchored regex validating provider and model slug syntax without traversal segments |

## Normalized chat model schema

Field contracts for normalized chat model hashes returned by `Llm::OpenRouterModelsService.call` and `lookup`.

| Field | Type | Description |
| --- | --- | --- |
| `:id` | `String` | Unique canonical model identifier (e.g. `"openai/gpt-4o"`, `"~deepseek/deepseek-pro-latest"`) |
| `:label` | `String` | Human-readable model name for admin selection, falling back to `:id` |
| `:supports_reasoning` | `bool` | True if model supports reasoning effort configuration via OpenRouter |

## Normalized decision model schema

Field contracts for normalized decision model hashes returned by `Llm::OpenRouterModelsService.decision_models` and `lookup_decision_model`.

| Field | Type | Description |
| --- | --- | --- |
| `:id` | `String` | Unique canonical model identifier (e.g. `"scaledown/classify-1"`, `"~typesafe/jev-latest"`) |
| `:label` | `String` | Human-readable model name for admin selection, falling back to `:id` |
| `:supports_reasoning` | `false` | Always false for System One decision models |
| `:mode` | `:decision` | Specialized mode discriminator distinguishing decision models from chat completions |

## Filtering and reasoning detection rules

Selection criteria applied to upstream OpenRouter models API responses.

- Item must be a Hash containing a non-blank `"id"` matching `SLUG_PATTERN`.
- When upstream includes `"supported_parameters"` array, `"structured_outputs"` must be present.
- `supports_reasoning` is true if `item.dig("reasoning", "supported_efforts")` is a non-empty Array or if `"supported_parameters"` intersects `["reasoning", "reasoning_effort"]`.
- Models are deduplicated by `:id` and sorted alphabetically by `:label` (case-insensitive, tie-breaking by `:id`).

## Decision model filtering rules

Selection criteria applied to OpenRouter models API responses for decision models.

- Item must be a Hash containing a non-blank `"id"` matching `SLUG_PATTERN`.
- When `"architecture"` is present, `item.dig("architecture", "output_modalities")` must be an Array including `"decisions"`.
- Minimal payloads omitting the `"architecture"` key are accepted.
- `:supports_reasoning` is set to `false` and `:mode` is set to `:decision`.
- Models are deduplicated by `:id` and sorted alphabetically by `:label` (case-insensitive, tie-breaking by `:id`).

## Cache and error handling contract

Execution outcomes for cache hit, miss, force refresh, and network failure.

| Condition | Cache interaction | Return value | Failure action |
| --- | --- | --- | --- |
| Cold cache (miss) | Write on API success | Fresh Array of model hashes | Log warning and return empty array on failure |
| Warm cache (hit) | Read from `Rails.cache` | Cached Array of model hashes | None |
| Force refresh (`force_refresh: true`) | Write on API success | Fresh Array of model hashes | Log warning and return stale cached array or empty array on failure |
| Upstream failure (HTTP 5xx, timeout, bad JSON) | Do NOT write failure to cache | Stale cache or `[]` | `Rails.logger.warn` with exception class and message |

## Dynamic route resolution contract

Precedence hierarchy and resolution outcomes for `Llm::ModelCatalog.lookup` across baseline routes, dynamic cache entries, and persisted settings.

| Resolution tier | Condition | Returned route | Failure action |
| --- | --- | --- | --- |
| 1. Baseline route | `ALL_ROUTES.key?(key)` | Static `ModelRoute` | Proceeds to tier 2 |
| 2. Dynamic cache entry | `Llm::OpenRouterModelsService.lookup(key)` or `.lookup_decision_model(key)` | Dynamic `ModelRoute(provider: :openrouter, api_model: id, label: label, supports_reasoning: supports_reasoning, mode: mode)` | Proceeds to tier 3 |
| 3. Cold-cache fallback | `valid_slug?(key) && AdminSetting.stored_model?(key)` | Dynamic `ModelRoute` with `mode: :decision` (`supports_reasoning: false`) when stored in `AdminSetting#decision_model`, `mode: :extraction` (`supports_reasoning: false`) when stored in `AdminSetting#extraction_model` (and not `summarization_model`), and `mode: :chat` (`supports_reasoning: true`) otherwise | Proceeds to tier 4 |
| 4. Unmatched choice | Unmatched string or wildcard | `nil` (`.lookup`) or raises `Llm::UnknownRouteError` (`.fetch`) | None |

## Request-level catalog lookup caching

Optional `catalog_models` parameter contracts for `Llm::ModelCatalog.lookup` and `Llm::OpenRouterModelsService.lookup`.

| Method | Signature | Behavior |
| --- | --- | --- |
| `Llm::OpenRouterModelsService.lookup` | `(key, models: nil)` | Finds model matching `key` in `models` if provided; otherwise calls `.call` |
| `Llm::OpenRouterModelsService.lookup_decision_model` | `(key, models: nil)` | Finds model matching `key` in `models` if provided; otherwise calls `.decision_models` |
| `Llm::ModelCatalog.lookup` | `(key, catalog_models: nil)` | Forwards `catalog_models` to `OpenRouterModelsService.lookup` during dynamic resolution |
