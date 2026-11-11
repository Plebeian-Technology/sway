---
mode: explanation
summary: "How ClassificationPromptBuilder::PROMPT_VERSION fingerprints the prompt for cache invalidation, and why its probe constants are built the way they are."
status: agent-extracted
related: [testimony-classification-prompt-design.md]
---

# Testimony classification prompt versioning

`Testimony::ClassificationPromptBuilder::PROMPT_VERSION` is a fingerprint of
the prompt, used as part of the cache lookup key so a saved verdict only
counts as a hit when it was produced by this exact prompt.

## Why the version is computed, not hand-bumped

`PROMPT_VERSION` is computed from the prompt's actual bytes rather than a
number someone edits by hand. A hand-bumped version is a rule nobody
enforces, and forgetting to bump it leaves misjudged documents excluded from
re-classification forever — bumping the version is the only way a wrong
`"not_testimony"` verdict ever gets corrected.

It hashes BOTH halves of the prompt: `#system_prompt` and `#user_message`,
including `#user_message`'s numbering template and its sanitizers. An
earlier version hashed `#system_prompt` alone, which let changes to the
other half happen without moving the version.

It also hashes the JSON schema sent with the request
(`config/schemas/testimony_classification.json`), because the schema's
`title`/`description` reach the model on every call
(`Llm::StructuredOutputSchema.for_request` keeps them) and are as much a part
of the question as the prompt text — excluding them would let an edited
schema change the question while every cached verdict kept standing.

The hash is computed once, at load time, over a fixed probe document rather
than the caller's live document list, so it does not re-version — and
invalidate the whole verdict cache — on every call. Over-invalidation (a
no-op prompt edit still re-classifies) is the accepted cost; the alternative,
under-invalidation, is permanent evidence loss.

## Why the probe constants look the way they do

`PROBE_NAME` and `PROBE_TEXT` are the fixed inputs `PROMPT_VERSION` is
computed over — never sent to a real model. Each is built to run past its
corresponding length cap (`MAX_NAME_CHARS` / `MAX_DOCUMENT_CHARS`) and to
carry every registered `Llm::UntrustedTextBlock` boundary prefix, lower-cased
and repeated, plus both Markdown code-fence styles. That is deliberate: a
probe missing any of those inputs would leave changes to them invisible to
`PROMPT_VERSION`, and bumping that version is the only correction path for a
wrong verdict.

`PROBE_TEXT` is built from distinct literal bytes rather than reusing
`PROBE_NAME`, so that swapping the NAME and TEXT slots in the prompt would
move the digest instead of silently canceling out. A spec pins both bounds,
since either one could stop mattering without anyone noticing.

Prefixes are read off the shared `Llm::UntrustedTextBlock::PREFIXES`
registry rather than listed by hand in these constants, so adding a new
content class elsewhere in the app also moves this version — again,
over-invalidating (one extra classification pass) is the safe direction
versus permanently losing evidence.

Both constants use `-(...)` (unary minus) rather than `.freeze`: RuboCop's
`Style/RedundantFreeze` autocorrect silently drops a trailing `.freeze` from
a string literal that uses interpolation, which would leave this
security-relevant constant mutable. Unary minus survives the cop and keeps
the same frozen guarantee.

## What version_probe_text is for

`#version_probe_text` returns the exact bytes `PROMPT_VERSION` hashes: both
prompt halves plus the schema, with the instance's random untrusted-text
delimiter replaced by the fixed `NORMALIZED_DELIMITER`. Too little
normalization and the version would inherit the delimiter's randomness,
re-billing every undecided document to the model on every restart; too much
normalization and the version would stop moving when the prompt actually
changes, caching verdicts against a stale question forever.
`classification_prompt_builder_spec` pins both directions by their
consequence, not by inspecting the string.

## The supporting constants

`PROBE_DOCUMENT` is what `.version_digest` hashes: a `Hash`, matching
`#initialize`'s shape, so the probe travels the same production path it
verifies rather than a hand-rolled shortcut.

`DELIMITER_PREFIX` is read from the shared
`Llm::UntrustedTextBlock::PREFIXES` registry rather than hand-copied, so
every other block in the app that neutralizes this content class stays in
step with it.

`NORMALIZED_DELIMITER` keeps `DELIMITER_PREFIX` (so renaming that prefix
still moves `PROMPT_VERSION`) but normalizes away the unguessable
per-instance suffix — the same too-little/too-much trade-off described
above for `#version_probe_text` as a whole.

`#boundary_instruction` lives in `#header` (the cacheable half of the
prompt) rather than `#user_message`: it names only the fixed delimiter
prefix, never the random suffix, so it doesn't break Anthropic's prompt
cache prefix match or add a second source of per-instance randomness to
`PROMPT_VERSION`.

`.version_digest` is kept as its own method rather than inlined into the
`PROMPT_VERSION` constant assignment, so a test can re-run it against a
changed prompt and confirm the version moved.
