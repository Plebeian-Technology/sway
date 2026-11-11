---
mode: explanation
summary: "Explains BillSummaryPublication's three-case rule for whether a finished generation may publish over bills.summary, and why it never overwrites words a person wrote."
status: agent-extracted
related: [bill-summary-published-vs-draft-box-bug, bill-summary-ai-unreviewed-detection]
---

# Why `BillSummaryPublication` refuses to publish in exactly one case

`BillSummaryPublication.publishable?` decides whether a finished generation
can put its summary on the public bill page. It never lets a run write over
words a person wrote.

## Publishing is the default

A finished generation publishes itself. Any machine-written text nobody
revised carries a notice that says so. Publishing is therefore the default.
The whole question here is the one exception: a summary a person wrote must
survive.

## How this tells the two apart, with no new column

The model keeps its draft on `bill_llm_provisionings.llm_summary`.
Publishing copies that draft into `bills.summary`, so the two match
straight after a publish. Three things can be true of the text already
published:

| Published text | Meaning | Verdict |
| --- | --- | --- |
| empty, or still `Bill::SUMMARY_PLACEHOLDER` | nothing is published — the placeholder summarizes nothing | Publish |
| equals the previous draft (`llm_summary` as it stood before this run's write) | this is the last draft; an earlier publish put it there and no person touched it | Publish |
| anything else | not empty, not the placeholder, and not the draft; only a person writes this column while the draft stays behind, so a person wrote it | DO NOT PUBLISH |

## Why the third case matters

A save once put the model's draft over an admin's words, under a green
success message — the fix for that is described in (see
[bill-summary-published-vs-draft-box-bug.md](bill-summary-published-vs-draft-box-bug.md)).
Auto-publish must not open it again, and this is the line that keeps it
shut.

## What happens when it refuses

The generation still writes its new draft. The published text and the
draft then differ. `Bill#summary_ai_unreviewed?` reads that as "a person
wrote this", so no notice appears. The refusal and the notice agree by
construction — neither has to be kept in step with the other.

## Why it takes the previous draft as an argument

The caller runs inside the lock that is about to replace `llm_summary`. It
holds the only copy of the text being replaced. If this class read the row
itself, it would read the NEW draft, and the middle case above could never
be true.
