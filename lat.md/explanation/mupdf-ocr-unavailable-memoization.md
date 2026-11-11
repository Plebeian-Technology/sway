---
lat:
  mode: explanation
---

# Why the "OCR unavailable" memo is keyed off the exception's class

When `#run_ocr` rescues `OcrUnavailable`, it selects that branch by the exception's CLASS, not by matching text in its message.

## Why class, not message text

`#run_mutool` tests the "OCR Disabled in this build" signature against the FULL stderr.

But the message an exception raises with is truncated — capped at 500 characters — and on the output-cap path, the message carries no stderr at all. Matching on class means the decision can no longer be lost to either of those length limits.

## Why self.class, not the literal class name

The memo write uses `self.class`, matching the read a few lines above it (`self.class.mutool_ocr_unavailable?`).

A class instance variable belongs to exactly one class. If a subclass of `MupdfExtractor` ever existed, writing to the literal class name here would mean the subclass reads its own (always-nil) copy while this code wrote to the parent's — and the memoization would quietly stop working.

What that would cost is the exact failure this memo exists to prevent: a doomed `mutool` OCR attempt retried for every image-only bill. No subclass of `MupdfExtractor` exists today, which is why nothing has gone wrong yet.
