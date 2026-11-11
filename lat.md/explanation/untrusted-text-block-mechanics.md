---
lat:
  mode: explanation
---

# How Llm::UntrustedTextBlock defends a prompt against the text it encloses

`Llm::UntrustedTextBlock` wraps text written by outsiders — public testimony, scraped bill text — in a boundary that text cannot fake, for prompts that must hand it to a model as DATA rather than as instructions.

See [[docs/explanation/untrusted-text-block-prefix-registry.md|untrusted-text-block-prefix-registry.md]] for why every enclosed content kind lives in one `PREFIXES` registry; this document covers the delimiter and neutralize mechanics themselves.

## Why a plain fence, or a structured-output schema, is not enough

A plain triple-backtick fence can be faked: a submission containing its own closing fence escapes the block, and everything after it reads as prompt rather than data.

Asking for a structured response does not save you either — a schema constrains the SHAPE of the answer, not its CONTENT, and a made-up summary or org position fits the schema perfectly.

## The delimiter: unguessable, and scrubbed on both sides

Each block is fenced by a tag ending in 16 random hex characters, generated fresh per instance. Nobody can guess it from a prompt they saw earlier — that unguessability IS the security property.

The text inside is also scrubbed, so nothing in it can blur the one boundary the prompt tells the model to trust.

## History: one shared class instead of two copies

This logic used to live as private methods on `BillPositionsPromptBuilder`, while `BillSummaryPromptBuilder` wrapped the SAME untrusted content in plain fences — protected in only one of two places.

It sits here as one shared class so there is a single implementation to harden instead of two to keep in sync.

## FENCE_REPLACEMENT: why fences are replaced, not deleted

Fences are replaced, not deleted, so the model can still tell a fence was meant to be there.

## BOUNDARY_MARKER_REPLACEMENT: why it must not contain a registered prefix

This replacement text must not contain any registered prefix, in any letter case.

`gsub` never re-scans what it just wrote, so a replacement carrying a prefix would put back what it removes. `.validate_prefix!` checks that over the whole registry when this file loads.

## FENCE_PATTERN: three kinds of boundary noise

None can FORGE the block, but all muddy it: backtick fences, tilde fences (Markdown accepts either as a closer), and text shaped like the delimiter tag.

## ALL_PREFIXES_PATTERN: why the longest prefix matches first, and why matching is case-insensitive

Longest prefix first, so the match never stops at a shorter registered prefix that starts a longer one. No current prefix starts another, but the ordering means a future pair can't break this.

Matching ignores letter case. A `gsub` against a plain `String` is case-sensitive, and a payload once slipped past the scrub just by holding shift.

## .for: naming the kind of content instead of repeating its string

This is how production code builds a block: name the kind of content instead of repeating its string.

## .validate_prefix!: why it runs as a class method at load time

Checks that a prefix does not appear inside the replacement text. It's a class method so it can run over the whole registry at load time AND be called directly by a test.

Checking inside `#initialize` alone is no longer enough: a colliding prefix now breaks the scrub in EVERY block, not only its own.

## initialize: what prefix must be, and why

The fixed, prompt-visible part of the delimiter (for example `"TESTIMONY-BOUNDARY"`) names the kind of content so the model's instructions can point at it; the unguessable part is the random suffix.

It MUST be one of the values in `PREFIXES`.

## wrap: why the rewrite grows the payload, and what that means for a size cap

THE BODY IS REWRITTEN HERE, AND THE REWRITE GROWS IT. `.neutralize` turns each prefix into `BOUNDARY_MARKER_REPLACEMENT`, and the shortest prefix (18 chars) is shorter than the 26-char replacement.

A payload made of nothing but prefixes comes out 1.444x its input length. Anyone may hand a PDF to a Baltimore City Council hearing, so that payload is an input, not a curiosity.

A CALLER WITH A CHARACTER BUDGET MUST CALL `.neutralize` BEFORE IT MEASURES. A cap on raw text is not a cap on what is sent: both builders cut to cap, then wrapped 150,000 chars into 216,658 sent.

`.neutralize` is idempotent — `BOUNDARY_MARKER_REPLACEMENT` carries no registered prefix (validated at load) and `FENCE_REPLACEMENT` isn't matched by `FENCE_PATTERN`, so a second pass changes nothing.

The `text` argument must already be valid UTF-8. `.neutralize` runs regular expressions, which raise on invalid bytes. Both callers clean the text at their own last checkpoint before it reaches here.

## .neutralize: why it scrubs every registered prefix, not only its own

Scrubs EVERY registered prefix, not only any one block's own. No payload has a legitimate reason to carry any of them, and watching only for its own leaves the other boundaries blurred.

It is a CLASS method because it reads no instance state. That lets a caller neutralize before it measures without reaching for the block it will wrap with, and lets a two-block wrap use one call.

## instruction: why it names only the fixed prefix

The paragraph that tells the model what the delimiter means.

Both callers put this text in the part of their system prompt that Anthropic can cache, so it inserts the FIXED prefix and never the random per-instance suffix.

Text that differs on every call would miss the cache every time: a 0% hit rate, paying the cache-write surcharge and never getting a cheap read back.
