---
lat:
  mode: explanation
---

# Why Llm::PromptCache exists

See also `docs/reference/llm-prompt-cache-thresholds.md` for the exact values this module uses.

## The silent failure this module exists to close

Anthropic's prompt cache has a minimum cacheable prefix that varies by model, with no simple pattern — a stronger model doesn't always have a lower one.

A block shorter than its model's minimum is quietly not cached: no error, `cache_creation_input_tokens` stays 0, nothing extra charged. That silence is the whole problem — nothing anywhere reveals a wrong assumption.

Earlier work attached the cache marker assuming Haiku's minimum was 1024, then built stability machinery on top of that assumption, and nothing anywhere could have revealed it was wrong. The marker is now attached only when the block can actually clear the minimum of the model the call is going to.

Getting the estimate wrong is cheap either way: attaching a marker that can't take effect does nothing, and holding one back that would have worked only misses a discount. Neither raises an error — which is exactly why the wrong Haiku assumption went unnoticed until someone checked it directly against Anthropic's documentation.

## Why retired models stay in the threshold table

Three of the six threshold rows are no longer selectable.

Three of the six threshold rows are no longer selectable — `AdminSetting::SUPPORTED_MODELS` is exactly haiku-4-5/sonnet-5/opus-5, so `claude-sonnet-4-5`, `claude-sonnet-4-6`, and `claude-opus-4-8` are rows no operator can pick today.

They are not rows with no caller, though. `#resolve_model_for` (`GenerateBillSummaryJob`, duplicated in `BackfillBillCategoriesJob`) returns `AdminSetting.singleton`'s PERSISTED column, which no migration rewrites — an old row saved before a model's retirement still returns the old model name. The rows stay because they're still consulted in the one environment that matters, and because a model missing from the table attaches the marker anyway — the wrong direction to drift by accident. **Do not delete a row here just because `AdminSetting::SUPPORTED_MODELS` no longer offers it as a choice** — a grep for callers of that model name will come up empty while a live, persisted `AdminSetting` row still returns it.

A prior version of this file argued the opposite: "these rows cannot be reached today." That premise invited its own deletion — a grep finds no caller, removes the row, and Anthropic silently declines the marker for whatever legacy model is still live in an old `AdminSetting` row.

`claude-opus-4-8` used to be left out of the table as "minimum not confirmed." It's confirmed now, read off Anthropic's published table — the gap was closed by finding the real figure, not by guessing it.

## What the three selectable floors mean in practice

An operator can pick three models today, and the table gives them three different floors: haiku 4.5 at 4096, sonnet-5 at 1024, opus-5 at 512.

Of the four prefixes this app sends, the first three — summary, positions, classifier — clear 1024, so they cache on sonnet-5 and opus-5 but are withheld on the haiku 4.5 default. The categorize prefix clears none of the three floors, opus-5.5's 512 included.

Opus 5's 512 is the lowest minimum in the table, so a prefix between 512 and 1024 tokens caches there and nowhere else — and this app sends no such prefix today. `prompt_cache_spec`'s `cacheable?` examples pin each of these statements to a concrete size, rather than repeating a number here that could go stale.

## The token-estimation ratio drifted twice

`CHARS_PER_TOKEN` is the one place that ratio is defined.

It once read 4.0 in this file while the environment-gated prompt-builder check and `CachePrefixTokenizer` both said 3.5 for the same thing. 4.0 leans toward *withholding* the marker: it estimates fewer tokens for the same text. A 1024-minimum model's 4000-character prefix estimated 1000 tokens under the 4.0 rule and lost its marker, where the 3.5 rule gives 1142 and keeps it.

Anywhere the character count sits between `3.5 * minimum` and `4.0 * minimum`, the app paid full input price on every call with no error, no log line, and no failing test — the exact failure this module exists to end. `CachePrefixTokenizer::TIER_2_CHARS_PER_TOKEN` now reads this constant directly, and a spec keeps the two in step so they can't drift apart again.

## Why the near-miss log has a band instead of firing on every miss

The log exists so a near miss can be seen rather than guessed at.

Without a band it defeats its own purpose: the `positions`/`classifier` prefixes clear no minimum on the default model (Haiku 5.5), so an unconditional log would fire on every single call.

The band starts at `0.75 * minimum`. Both of the app's near-default prefixes sit far under that line. 0.75 is a judgment call, not a measurement: too low brings back the flood of warnings on every call; too high loses a log line about a standing fact of the prompt rather than an actionable event. No caching behavior depends on the ratio — it only decides whether the withholding gets said out loud.

## Why the model-name match takes the longest prefix, not the first

`.minimum_prefix_tokens` used to be `Hash#find`, which walks rows in written order — so where two model families exist and one name is a prefix of the other, the row written first won, no matter which was more specific.

No such pair sits in today's table, but Anthropic's naming produces exactly that shape routinely (`claude-opus-4` alongside `claude-opus-4-8`), which would have silently returned the wrong minimum for the newer model.

`Llm::UntrustedTextBlock::ALL_PREFIXES_PATTERN` makes the identical argument for its own prefix list — same reasoning, same fix, on a code path that is also deciding whether to make a network call.
