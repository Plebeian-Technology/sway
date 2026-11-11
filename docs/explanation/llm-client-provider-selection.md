---
mode: explanation
summary: "Explains why Llm::Client.build re-reads Sway::Settings.llm on every call instead of caching the provider, why an unknown provider fails fast, and how a blank LLM_PROVIDER is repaired before this method ever sees it."
status: agent-extracted
related: [llm-settings-group-design]
---

# Why `Llm::Client.build` re-reads the provider setting on every call

`Llm::Client` is the single entry point `GenerateBillSummaryJob` uses to
pick which LLM adapter to build, based on `LLM_PROVIDER`. It defaults to
`"llamacpp"` (dev/test); production sets `LLM_PROVIDER="claude"` via
`env.clear`.

Unknown providers fail fast — this module does NOT silently fall back. The
two supported providers form a deliberate allowlist.

## Why the setting is consulted on every call, not hoisted into a constant

`Sway::Settings.llm` is consulted on EVERY CALL, not once when the method
is defined — do NOT hoist this into a class constant. The group itself is
memoized one level down, built once per process at boot, in the
`sway.settings` initializer. An operator swapping `LLM_PROVIDER`
still recovers by redeploying, which restarts the process and rebuilds the
group; a same-process `LLM_PROVIDER` change no longer takes effect, and
nothing in this codebase relies on one.

## Why a blank `LLM_PROVIDER` no longer raises outside the job's rescue chain

A blank `LLM_PROVIDER` (a typo, a `kamal env push` slip) used to raise
`ArgumentError` outside the job's rescue chain, and every bill summary job
got stuck in `generating` with no `mark_failed!` firing.
`Sway::Settings.llm.llm_provider` now repairs an empty OR whitespace-only
value back to its own default before this method ever sees it, in
one place, for every setting — what used to be a second `ENV.fetch`
fallback here.

## Why the caller's argument is still stripped and checked separately

The strip-and-check on the `provider:` argument is for the CALLER'S
argument only, which never reaches the declaration:
`provider: ""` (`BackfillBillCategoriesJob`, `GenerateBillSummaryJob` and
`Testimony::AttachmentClassifier` all pass an explicit `provider:`) still
has to fall through to the setting.
