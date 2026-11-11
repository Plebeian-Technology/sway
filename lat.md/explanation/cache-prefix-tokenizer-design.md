---
lat:
  mode: explanation
---

# Why CachePrefixTokenizer has two tiers, and how it stays safe without the gem

`CachePrefixTokenizer` counts the tokens in a cacheable prompt prefix, in one of two ways:

- **Tier 1 (the accurate one).** When someone has opted into live LLM
  traffic (`LiveLlmGate` — `RUN_LIVE_LLM_TESTS=1` AND a non-blank
  `ANTHROPIC_API_KEY`) and the `anthropic` gem is loaded, it calls
  Anthropic's free `count_tokens` endpoint and returns the `input_tokens`
  number it reports.
- **Tier 2 (the fallback).** When anything Tier 1 needs is missing, it
  returns `nil` so the caller can estimate from the text length instead, at
  `TIER_2_CHARS_PER_TOKEN` characters per token — see
  `docs/explanation/llm-prompt-cache-silent-failure.md` for why that ratio
  is BORROWED from `Llm::PromptCache::CHARS_PER_TOKEN` rather than
  restated: the two used to drift (one said 3.5, the other 4.0), and the
  4.0 direction quietly dropped the cache marker on real prefixes.

`require "anthropic"` is wrapped in `begin`/`rescue LoadError` so this file still loads in a fresh clone that does not have the gem installed yet. There, Tier 1 returns `nil` unconditionally and the caller falls through to Tier 2. Once the gem is installed, Tier 1 does the real work.

## What count's returned token count includes

The `input_tokens` count `#count` returns INCLUDES the 3-4 tokens spent on a throwaway user message: Anthropic's `count_tokens` endpoint needs at least one user turn, and the SDK has no system-prompt-only mode.

Callers subtract about 4 to estimate the prefix on its own, or assert `>= 1028` to clear the 1024-token cache minimum with that fixed overhead already counted in.

## Why the live-calls opt-in is checked before the API key

`#count` checks that someone ASKED for live calls (`LiveLlmGate.enabled?`) before checking that an API key exists.

This used to check the key alone, so a plain `rspec` run in a dev shell with `ANTHROPIC_API_KEY` exported went out over the network — which also made the prompt-cache check's result depend on whatever the shell happened to have set, rather than on the prompt being tested. Opting in to live calls takes two things; this ordering is the half that was missing before.

The key itself is trimmed before both the blank check and its use in the request. A key with a trailing newline — the ordinary result of `$(cat key.txt)` or a copy-paste — is not blank, so an untrimmed check would wave it through into the `x-api-key` header value.

## Why every Anthropic::Errors::Error becomes nil, not a raised failure

ANY `Anthropic::Errors::Error` from Tier 1.

ANY `Anthropic::Errors::Error` from Tier 1 — an invalid key, a 401 `AuthenticationError`, a passing `APIConnectionError`, a slow `APITimeoutError`, and so on — must end up as `nil` so the caller can estimate from text length instead. Without this rescue, `spec/services/bill_summary_prompt_builder_spec.rb` dies mid-run with a confusing `AuthenticationError` stack trace whenever `ANTHROPIC_API_KEY` is set but wrong: a rotated key, the wrong vault entry, or the placeholder `"sk-ant-test-key"` leaking out of `claude_adapter_spec.rb`.
