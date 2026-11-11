---
lat:
  mode: explanation
---

# Why LlmSummaryStaleHeader is laid out the way it is

The out-of-date badge and the Regenerate button are drawn together as one block above the existing summary, which stays readable. The badge names whichever change actually overtook the summary — see [[docs/explanation/stale-change-detection.md|stale-change-detection.md]].

## The chip is NOT repeated here

The "where it came from" chip is NOT repeated here.

`LlmSummaryCompletedView` is the only place that draws it, and a test guard requires each `data-testid` to appear once. A second identical chip one row above would be noise, not emphasis. What this screen owes the operator is a warning at the moment of the destructive act, and the confirmation dialog carries it now — see `llmProvider`, passed along for exactly that (see [[docs/explanation/operator-paste-provenance-marker.md|operator-paste-provenance-marker.md]]).

## The hover text follows the chip's own moment

The hover text is the exact moment behind the chip's relative wording, so it has to follow the same moment the chip names. Left on `diff_generated_at` it would contradict the sentence above it.

## onRequestRegenerate opens a confirmation, and used not to

Opens the confirmation dialog.

It used to call `onRegenerate` straight away. On an out-of-date row this is the ONLY regenerate button, because `LlmSummaryCompletedActions` hides its own confirmed one with `{!stale && ...}` — and a pasted summary counts as out of date forever. So the one unconfirmed control on the screen was also the one most likely to destroy work that cannot be recovered.

## Why LlmSummaryCompletedActions hides its own button here

When the out-of-date header shows its own "Regenerate from latest data" button, `LlmSummaryCompletedActions` hides its own so there are not two of them.
