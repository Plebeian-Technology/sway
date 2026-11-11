---
mode: how-to
summary: "How to run spec/integration/llm/claude_adapter_integration_spec.rb against the live Claude API, and what its 9 live calls cost."
status: agent-extracted
related: [docs/explanation/live-llm-http-policy-double-gate.md]
---

# Running the live Claude adapter integration spec

`spec/integration/llm/claude_adapter_integration_spec.rb` is skipped by
default. A full run makes 9 live Claude API calls and spends real money —
price it against current Anthropic rates before running, using the
breakdown below as a starting point, not a fixed number.

## What the 9 calls are for

5 calls on Claude Haiku 5.5, the model operators use by default:

- 1 checking the summary matches its schema
- 1 checking that Haiku does not cache (its cacheable-prefix floor is above
  this prompt's size)
- 1 checking the summary's `stop_reason`
- 2 for positions — schema match and `stop_reason` on
  `generate_bill_positions`, which had never once been sent to the real
  endpoint before this spec existed

4 calls on Claude Sonnet 5.5:

- 2 for the example that writes the cache and then reads it (one example
  making both calls itself, so it controls its own call order rather than
  depending on suite run order)
- 2 for the cross-bill cache read

The Sonnet calls have to run on a model whose minimum cacheable prefix this
prompt's roughly 2,246-token system block actually clears. `count_tokens`
calls, made whenever `CachePrefixTokenizer` runs, are free and do not count
toward the 9.

As of May 2026 Haiku prices against a bill source of roughly 2k tokens, the
Haiku part alone cost about $0.03-0.10 per run, and Sonnet 5.5 costs
noticeably more per token than Haiku. Work the total out again from current
Anthropic pricing before running — do not assume that figure still holds.

## Prerequisites

Running this spec takes two things:

- `ANTHROPIC_API_KEY` (the credential) — exported in your shell, typically
  loaded from your secret store.
- `RUN_LIVE_LLM_TESTS=1` (the intent) — see
  [../explanation/live-llm-http-policy-double-gate.md](../explanation/live-llm-http-policy-double-gate.md)
  for why the credential being present is not treated as consent to spend
  money, and how the suite enforces that everywhere a live call could go
  out, not just in this one file.

CI has neither, so it sees the file as skipped and green.

## Command

```
RUN_LIVE_LLM_TESTS=1 dip run bundle exec rspec \
  spec/integration/llm/claude_adapter_integration_spec.rb
```
