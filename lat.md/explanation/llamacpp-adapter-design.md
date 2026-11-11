---
lat:
  mode: explanation
---

# How Llm::LlamacppAdapter builds and guards its requests

`Llm::LlamacppAdapter` is the adapter used in development and test.

It calls a llama.cpp server on the developer's own machine at `/v1/chat/completions` via `ruby-openai`, since llama.cpp accepts requests shaped like the OpenAI API.

Messages are sent as a system message plus a user message, split the same way as the Claude path, so llama.cpp's grammar sees the same shape. No `cache_control` field is sent — llama.cpp ignores it.

For the `generate_bill_categories`, `generate_bill_positions`, and `generate_testimony_classification` methods, see `docs/explanation/claude-adapter-design.md`'s "The `generate_*` public methods all route through one private body" section — the rationale (each response is checked against its own fixed schema constant, never the caller's `schema:`) is identical between the two adapters. This adapter additionally exists for `generate_testimony_classification` so dev/test can classify attachment names offline, without a live Claude call.

## .request_timeout_seconds: why 120s assumes an immediate-answering model

120s suits a model that answers immediately, not one that thinks first — a local reasoning model can spend minutes before its first token, which this deadline can't tell apart from a hung server.

Raising this alone doesn't fix a timeout — see `.thinking_enabled?` below for the actual fix (the real limit is the output token budget). The value stays settable for slower machines or larger models.

The setting is read on every call rather than frozen into a constant, so a spec that swaps the setting (`with_app_config`) between examples sees the change. The value itself is memoized one level down, in `Sway::Settings.llm`, built once per process at boot — an operator swapping `LLM_REQUEST_TIMEOUT_SECONDS` still recovers by redeploying, which restarts the process and rebuilds it; nothing in this codebase changes it mid-process.

Zero and negative fall back to the default. A 0 timeout means NO deadline, so a mistyped value would switch the guard off instead of tightening it — see `docs/explanation/llm-settings-group-design.md#who-owns-the-four-caps-zero-or-negative-fallback` for why that rule lives at the caller (this method), not in `Sway::Settings::Llm` itself. Unreadable text (`LLM_REQUEST_TIMEOUT_SECONDS=soon`) is a DIFFERENT case: `Sway::Settings::Llm`'s strict integer caster raises when the group is built, rather than reaching this method as zero — this fallback is what is left over, for a real, readable zero or negative value.

## .thinking_enabled?: asking the chat template not to think first

A local reasoning model writes its working out first as `reasoning_content` (never read here) — those tokens count against `MAX_TOKENS`, so it can spend the whole budget and never begin the JSON.

This is what lets the FULL prompt through without lowering the source cap for a local model.

The tradeoff: a reasoning model usually answers better when it thinks; here it usually answers nothing, and a summary beats none. Only this dev/test path is affected — `ClaudeAdapter` is untouched.

Setting `LLM_LLAMACPP_THINKING=1` restores thinking for a model or template that needs it. See `docs/explanation/llm-settings-group-design.md#llm_llamacpp_thinking-widens-the-switch` for why it is declared `:boolean` and what that widens over the old `== "1"` comparison it replaced.

## generate_structured: the shared body

The shared body behind the public `generate_*` methods differs only in the `json_schema` `name:` and which checker validates the response. It's kept separate so a caller can't loosen the check.

`response_format` sends `json_schema` (not `json_object`) so llama.cpp constrains sampling token by token against the schema — see `docs/explanation/llamacpp-structured-output-conformance.md` for why the plainer `json_object` form lets small models (gemma-3/4-E2B) drift into valid JSON with the wrong key names, which then fails schema validation.

`chat_template_kwargs: {enable_thinking: ...}` reads `.thinking_enabled?` (above) — reasoning tokens are never read here and they are what exhausts `max_tokens` on a local reasoning model.

### Why finish_reason is checked before content

`finish_reason` is checked FIRST, so a truncation that also produced zero content reports the real cause (`max_tokens`) instead of "empty response". This mirrors the Claude path's `stop_reason == "max_tokens"` check.

The truncation raises `Llm::SchemaError`, not `Llm::TransportError` — same reasoning as `ClaudeAdapter`'s `stop_reason` branch (see `docs/explanation/claude-adapter-design.md#why-a-stop_reason--max_tokens-truncation-is-llmschemaerror-not-llmtransporterror`). These two adapters are one agreement: change together or drift apart, a bug class this code has hit before — see `docs/explanation/llm-adapter-shared-contract-drift.md`.

`.strip.empty?`, not `.empty?`, matches `ClaudeAdapter`'s empty-body check, treating a blank body as transient network noise. Without it, a whitespace-only body slipped into `JSON.parse` and got DISCARDED instead of retried.

Parse-and-validate is shared with `ClaudeAdapter` via `Llm::SchemaValidator`. The literal `"llama.cpp"` (`provider_label` omits the dot) keeps log searches working ("from llama.cpp:" / "from claude:"). The normalizer takes its schema hash from the checker built at boot, not a caller-suppliable `schema_hash:` that could loosen the check — the same change made on the Claude side.

## client: why there is no shared .llamacpp Faraday builder

`ruby-openai` 7.x accepts a middleware block, run AFTER the gem's default middleware.

It mounts `:retry` with the SAME profile as `Sway::FaradayStack::LLAMACPP_DEFAULTS`, so 5xx/timeout retries before raising — see `docs/explanation/faraday-stack-retry-and-connection-design.md#why-there-is-no-llamacpp-connection-method` for why this adapter borrows only the retry options from that module instead of a shared connection method.

## transport_error_detail: surfacing the response body, not just the exception class

`Faraday::Error#message` is generic and drops the response body. For llama.cpp the body IS the diagnosis (e.g. `exceed_context_size_error`). Surfacing it lets failures be debugged from the log alone.
