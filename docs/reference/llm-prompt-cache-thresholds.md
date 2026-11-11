---
mode: reference
summary: "Lists the minimum cacheable prefix per model, the token-estimation ratio, and the near-miss log band Llm::PromptCache uses to decide whether to attach Anthropic's cache_control marker."
status: agent-extracted
related: [docs/explanation/llm-prompt-cache-silent-failure.md]
---

# Llm::PromptCache thresholds

<!-- vale Vale.Spelling = NO -->

`Llm::PromptCache` decides whether a system prompt block is worth marking
`cache_control: {type: "ephemeral"}`. This page lists the exact values it
uses. For why they're set this way and the incidents that shaped them, see
`docs/explanation/llm-prompt-cache-silent-failure.md`.

## Minimum cacheable prefix per model

`MINIMUM_CACHEABLE_PREFIX_TOKENS` maps a model-id prefix to Anthropic's
documented minimum cacheable prefix, in tokens:

| Model id prefix | Minimum tokens |
| --- | --- |
| `claude-haiku-5-5` | 4096 |
| `claude-sonnet-4-5` | 1024 |
| `claude-sonnet-4-6` | 1024 |
| `claude-sonnet-5-5` | 1024 |
| `claude-opus-4-8` | 1024 |
| `claude-opus-5` | 512 |

Matching is against the START of the full model id (operators pick dated ids
like `claude-haiku-5-5`), and when more than one row's prefix
matches, the LONGEST matching prefix wins — not written order.

A model missing from this table means "minimum unknown" to `#cacheable?`,
which attaches the marker anyway.

Only `claude-haiku-5-5`, `claude-sonnet-5-5`, and `claude-opus-5` are
selectable today via `AdminSetting::SUPPORTED_MODELS`; the other three rows
exist for models no operator can currently pick. **Do not delete a row for
that reason** — `#resolve_model_for` (`GenerateBillSummaryJob`) returns
`AdminSetting.singleton`'s persisted column, which no migration rewrites,
so a live row can still return a retired model name after it drops out of
`SUPPORTED_MODELS`. See
`docs/explanation/llm-prompt-cache-silent-failure.md` for the full
reasoning.

## Token estimation ratio

`CHARS_PER_TOKEN` is `3.5`. `.estimated_tokens(text)` returns
`(text.length / 3.5).floor`. This is the single place that ratio is defined
in the codebase — `spec/support/cache_prefix_tokenizer.rb`'s
`CachePrefixTokenizer::TIER_2_CHARS_PER_TOKEN` reads it, and a spec keeps the
two in step.

## Near-miss log band

`NEAR_MISS_LOG_RATIO` is `0.75`. `.cache_control_for` logs
`llm.prompt_cache.withheld` when the estimated token count is at least
`minimum * 0.75` but still under `minimum` — a near miss, not every miss.
The log is diagnostic only; it does not change whether the marker is
attached.

## Decision methods

| Method | Returns |
| --- | --- |
| `.minimum_prefix_tokens(model)` | `Integer` minimum, or `nil` if the model isn't in the table |
| `.estimated_tokens(text)` | Estimated token count for `text` |
| `.cacheable?(system_prompt, model:)` | `true` if the minimum is unknown, or the estimate meets it |
| `.cache_control_for(system_prompt, model:)` | `{type: "ephemeral"}` when cacheable, else `nil` (with the near-miss log as a side effect) |
