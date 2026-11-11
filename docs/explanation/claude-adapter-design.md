---
mode: explanation
summary: "Explains Llm::ClaudeAdapter's request/response mechanics: its cost and timeout ceilings, its structured-output request shape, its error-rescue ordering, and how it resolves its API key."
status: agent-extracted
related: [llm-adapter-shared-contract-drift, llm-adapter-error-classification, llm-prompt-cache-silent-failure, llm-structured-output-schema-defects, env-secret-blank-value-handling]
---

# How `Llm::ClaudeAdapter` builds and guards its requests

`Llm::ClaudeAdapter` is the production-only adapter wrapping the Anthropic
SDK 1.x for bill-summary generation. Rails autoloads app code, not gems, so
`claude_adapter.rb` needs an explicit `require "anthropic"` at the top of
the file. Later `require "anthropic"` calls become safe no-ops for
`spec_helper` and `CachePrefixTokenizer`.

`system[0]` is marked `cache_control: ephemeral` so Anthropic's prompt cache
can fire on repeat calls; see `docs/explanation/llm-prompt-cache-silent-failure.md`
for the per-model floor.

Structured output uses `output_config.format` on `messages.create` — the old
`output_format` + `anthropic-beta` shape was removed and now returns 400.

The four `Anthropic::Errors` classes are rescued specific before general
(timeout/connection/rate-limit/auth before the generic `APIStatusError`), or
a broad class swallows a more specific one.

Second line of defense: the parsed response is re-checked against
`BILL_SUMMARY_SCHEMA` (or the caller's validation schema). A violation
raises `Llm::SchemaError`, which the job discards instead of retrying — see
`docs/reference/llm-adapter-error-classification.md`.

## The four ceiling constants

`MAX_TOKENS` (4096) is a per-call cost ceiling, not just an output cap — it
stops an expensive model like Opus running up an unbounded bill. It matches
the llama.cpp adapter's `MAX_TOKENS`. The Anthropic SDK requires
`max_tokens:` — there is no default; omitting it raises `ArgumentError`.

`DEFAULT_TIMEOUT_SECONDS` (120) matches llama.cpp's timeout default. It
must be passed as `request_options:` in `#generate_structured`, not the
client timeout — `Messages#create` silently overrides a non-default
client-level value. Do not cite a gem version or line number for that
override behavior — a Dependabot bump makes one stale with nothing in this
repo changing; re-read the installed gem, since `claude_adapter_spec.rb`
pins the real behavior. The client-level timeout is only the transport
default for non-messages endpoints — it is not the ceiling on the
`generate_structured` path.

`DEFAULT_MAX_RETRIES` (2) is the SDK-level retry budget: one initial call
plus two retries per job attempt. The worst-case wall-clock math (~1190s
across 3 job attempts) is asserted in `claude_adapter_spec.rb`, not restated
here.

`MAX_TRANSLATED_ERROR_LENGTH` (200) caps how much of the upstream error
message is echoed into translated `Llm::TransportError`/`Llm::SchemaError`
messages, so logs stay readable. It mirrors the job's
`MAX_GENERATION_ERROR_LENGTH` (500).

## The `generate_*` public methods all route through one private body

`#generate_bill_summary`, `#generate_bill_categories`,
`#generate_bill_positions`, and `#generate_testimony_classification` each
call `#generate_structured` with their own `validation_schema:`. Each
response is checked against that FIXED schema constant
(`BILL_CATEGORIES_SCHEMA`, `BILL_POSITIONS_SCHEMA`,
`TESTIMONY_CLASSIFICATION_SCHEMA`), never the caller's `schema:` argument —
an oversized or malformed response is rejected regardless of what the
caller passed in for the request.

`#generate_testimony_classification` backs the LLM fallback
`Testimony::NameRules' allow/deny rules can't decide (attachment-name
classification). Callers fix this to Haiku via
`Testimony::AttachmentClassifier::CLASSIFIER_MODEL`, not
`AdminSetting#summarization_model`. No effort/thinking/randomness is sent;
Haiku 5.5 rejects `effort`.

## `#generate_structured`: the shared body, and why it's shared

`schema` is sent in the request; `validation_schema` is the checker the
response is held to — kept separate so a caller can't loosen the check.

No temperature/top_p/top_k is sent: Opus 4.7+ rejects those randomness
settings with a 400, since they were removed on newer models. Tone and
repeatability are steered through the system prompt instead.

`request_options:` is the ONLY place the deadline takes effect (see
`DEFAULT_TIMEOUT_SECONDS` above). All four `generate_*` methods route
through this one private method, so the deadline can't be forgotten on the
next one added.

### Why a `stop_reason == "max_tokens"` truncation is `Llm::SchemaError`, not `Llm::TransportError`

The cap is DETERMINISTIC (same prompt, same `MAX_TOKENS`), so retrying
re-pays for a guaranteed failure — and gives a clearer diagnosis than
truncated JSON would. The empty-response check further down stays
TRANSIENT instead — a blank body can be network noise worth retrying. This
message reaches the operator via
`DeterministicBillSummaryError#generation_error`.

### Why the response is scanned for a text block instead of trusting `content.first`

`response.content` is an ordered list of blocks and the JSON is not always
in the first one: extended thinking prepends a `thinking` block ahead of
the `text` block (seen in production — `content[0].type ==
:thinking`, `stop_reason == :end_turn`, a normal completion the old
first-block check misread as a transport failure). Structured outputs can
also put the JSON into a `tool_use` block instead of text. Neither block
type has a `#text` method, so `&.text` on the wrong block would raise
`NoMethodError`, which slips past the rescue chain uncaught. The adapter
therefore searches `response.content` for the first block whose type is
`"text"` and raises `TransportError` only when none exists. That error
names the block types that were actually present
(`response.content.map(&:type)`) rather than presuming a single cause: the
earlier message blamed `tool_use` unconditionally and sent triage of the
thinking-block failure the wrong way. `tool_use` is still named as one
possibility, with the `output_config.format` request shape to verify.

### Why an empty response is transient, not a schema error

An empty response is treated as TRANSIENT (retried), not `Llm::SchemaError`
(discarded) — this chooses resilience to passing network noise over
protecting the budget from a misbehaving model.

### Parse-and-validate is shared with `LlamacppAdapter`

Parsing and validation goes through `Llm::SchemaValidator`, which raises
`Llm::SchemaError` naming the provider so log triage stays grep-able ("from
claude" vs "llama.cpp"). The checker built at boot is the ONLY schema that
comes in at this point — the caller's `schema:` shapes the request that is
SENT and nothing else; it can no longer decide what a response is held to.

## `#system_block`: when the cache marker is attached

`cache_control` goes on only when the block clears the model's minimum
cacheable prefix (see `docs/explanation/llm-prompt-cache-silent-failure.md`
and `Llm::PromptCache`). Below minimum, Anthropic silently skips caching —
an unconditional marker would lie. No prefix size is stated here on
purpose — past attempts to pin a number here went stale unnoticed;
`prompt_cache_spec.rb` asserts the real sizes and per-model floors.

## `#client`: built once per adapter instance

The Anthropic client is built once per adapter instance and reused across
calls on that instance. A fresh adapter (a new job run) builds a fresh
client. `timeout:` here is the transport default for endpoints OTHER than
`messages.create` — it is NOT the ceiling on the `generate_*` path. The
ceiling is applied per request in `#generate_structured`.

## `#api_key`: lazy resolution, and why a stripped guard matters

`#api_key` is resolved LAZILY — `#client` is first reached inside
`#generate_structured`, whose contract is to raise only
`Llm::TransportError` or `Llm::SchemaError`. A bare `ENV.fetch` would break
that with a bare `KeyError`.

`Llm::TransportError` is the right class here: a secret an operator
restores with `kamal env push` is recoverable without a code change,
matching the retryable contract. Blank counts as missing, same rule as
`Llm::Client`.

The key is read through `EnvSecret`, not an inline `.to_s.strip` — see
`docs/explanation/env-secret-blank-value-handling.md` for why `EnvSecret`
strips and treats blank as absent uniformly: "blank counts as absent" is
defined once instead of re-decided per call site, which is how a guard and
the value it checks can drift apart (a key with a trailing newline, a
common `kamal env push` artifact, could otherwise pass a hand-rolled guard
but still be sent, and get a 401).

## `#structured_output_args`: where schema-stripping happens

The response is held to the given schema via `output_config.format` on
`messages.create`. `JSONOutputFormat` carries only `type` and `schema` —
the old `output_format` shape was removed and now returns 400.

Stripping unsupported keywords happens in `Llm::StructuredOutputSchema`
(see `docs/explanation/llm-structured-output-schema-defects.md`), not per
call site, so a fifth call can't skip it, and llama.cpp's schema stays
untouched. Checkers still use the original, unstripped hashes.
