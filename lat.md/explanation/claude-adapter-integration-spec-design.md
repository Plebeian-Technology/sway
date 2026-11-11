---
lat:
  mode: explanation
---

# Why claude_adapter_integration_spec.rb's live examples are built this way

See [[docs/how-to/run-claude-adapter-integration-spec.md|Running the live Claude adapter integration spec]] for cost and invocation, and [[docs/explanation/llm-prompt-cache-silent-failure.md|Why `Llm::PromptCache` exists]] for the caching mechanism these examples exercise.

## Why the cache examples run on Sonnet, not the Haiku default

The cache examples cannot run on the Haiku default.

Haiku's minimum cacheable prefix is 4096 tokens and the system block sits below that floor (see `Llm::PromptCache`'s spec for the current measurement — repeating the number here has gone stale more than once), so on Haiku the cache can only ever report zero. The Sonnet tier's floor is 1024 tokens, which the same block clears, so Sonnet is the model that can prove the two things these examples exist for: that `cache_control` reaches the request at all, and that the prefix is byte-for-byte the same from one bill to the next.

Every example under "cache write + read" runs on `cacheable_model` for this reason, not on the model operators use by default: on Haiku 5.5 these assertions were asserting something false, and had never once run.

`other_bill` reuses the first bill's locale and legislator so only the bill-level inputs differ — exactly the content that used to leak into the cached prefix — and gets a different `scheduled_release_date_utc`, because `(scheduled_release_date_utc, sway_locale_id)` has to be unique.

## Why the schema-fidelity example no longer asserts draft_org_positions is absent

This example used to also assert `expect(result.keys).not_to include("draft_org_positions")`, which bets on the model's judgement rather than on anything this repo controls.

`bill_summary.json` still declares `draft_org_positions` as an optional property — kept so `paste_summary` keeps working, as its own description says — so structured outputs let the model send it, and only the prompt discourages it. A later point release that returned `"draft_org_positions": []` would turn this example red on a paid run, in a file that has already gone stale once, while the system was working correctly. The part the repo does control — that the prompt no longer asks for positions — is asserted for free and deterministically in `spec/services/bill_summary_prompt_builder_spec.rb`.

## Why the no-cache-on-Haiku example exists at all

The default model does not cache this prefix.

Every earlier claim to the contrary in this repo came from a threshold table with its numbers the wrong way round, which nobody could disprove because the spec was hidden behind an environment variable. If someone later grows the prefix past 4096 tokens, this example fails and sends them to read the prefix-size check in `spec/services/bill_summary_prompt_builder_spec.rb`, rather than quietly disagreeing with it.

## Why the positions call needed its own live example

The positions call had no live coverage at all.

`bill_positions.json` had never been sent to Anthropic as `output_config.format`, and `BillPositionsPromptBuilder`'s split into a system and a user message had never been tried against the real endpoint — so the first real attempt would have happened in production. That is the same gap the summary call closes, one call further down. The request really is shaped differently: a different schema, and a much shorter system block that carries no `cache_control` at all.

## Why the cache write/read split is now one example, not two

"creates the cache on call 1" used to be its own example, asserting `cache_creation_input_tokens > 0`.

Anthropic's cache lives on their server and is keyed by the content of the prefix, and the "reads it on call 2" and "reads across two different bills" examples make Sonnet calls against that same byte-stable prefix. So if either of them ran first, the "create" call was really a cache read, reported 0 creation tokens, and went red while everything worked. It only held together because `config.order = :random` happens to be commented out in `spec_helper.rb` — an unspoken reliance on a default setting, in a file that costs money to run. The create-then-read split is now proved by one example that makes both calls itself, so it controls its own order.

## Why a separate example reads the cache across two DIFFERENT bills

The same-bill example calls the same bill twice, so its system block is identical no matter what the builder puts in it.

The same-bill example calls the same bill twice, so its system block is identical no matter what the builder puts in it — it cannot catch a prefix that changes from bill to bill, which is exactly the defect that shipped. Production summarizes different bills, so that is the case worth paying for an API call to prove.
