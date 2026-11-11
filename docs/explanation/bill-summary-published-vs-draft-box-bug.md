---
mode: explanation
summary: "Explains the bug where the summary editing box was seeded from and saved to the wrong column, publishing the model's draft over an admin's hand-written summary."
status: agent-extracted
related: []
---

<!-- vale Vale.Spelling = NO -->

# The published-summary box held the wrong column

The Bill Creator's summary editing box holds the published summary
(`bills.summary`), and the model's draft (`bill_llm_provisioning.llm_summary`)
sits beside it. That was not always true: the box used to be seeded from the
draft column and saved back to the published column, under a label reading
"this is what users see." An admin who had written the public summary by
hand, opened the tab, and pressed Save — with or without an edit — published
the model's draft over their own text, with nothing on screen changing and a
green "Summary saved." toast.

## Why the bug went unnoticed

The system spec covering this box survived the fix unchanged for two
reasons. Its sibling example asserted only the SAVE side, which always wrote
`bills.summary` regardless of the bug — that was the bug. And the bill
factory fills `summary` with a Faker paragraph, so a failure would have read
as unrelated noise rather than as a column that had moved.

## The fix

The example now pins both halves of the contract in one browser view: the
published text is IN the box, and the draft is on screen BESIDE it rather
than in it. A future column move cannot satisfy one half quietly.

## The regenerate confirmation dialog made the same claim

The regenerate-summary confirmation dialog used to read "This will replace
the existing summary" — the one claim the notices around that fix
exist to deny: a regenerate run replaces the model's draft and never
touches the published summary, the box labelled as what readers see. The
sentence was corrected to "This will replace the model's draft summary.
The published summary below is not changed by this.", and
`spec/system/admin_summary_editing_spec.rb`'s confirmation-dialog example
asserts the corrected wording.

## `publishedSummary` prop notes

`BillCreatorLlmSummaryStatus` and `LlmSummaryCompletedView` both thread a
`publishedSummary` prop: `bills.summary`, the bill's PUBLISHED summary; the
editable box holds it and Save writes it. Separate from `provisioning`:
different record, and no code copies one to the other.

`LlmSummaryEditableSummary` is seeded from `bills.summary`, saved to
`bills.summary`. Used to seed from the model's draft instead, so any save
here silently published it over an admin's own text.

The draft isn't lost: `LlmSummaryDraftNotice` shows it beside the box with
a button to copy it in, so publishing it stays deliberate.

The confirm dialog used to say "This will replace the existing
summary", but only the draft is ever touched by regenerate — it must name
the draft, not the published text. `LlmSummaryCompletedView.test.tsx`
pins this at the component level.
