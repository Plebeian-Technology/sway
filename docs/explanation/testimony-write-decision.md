---
mode: explanation
summary: "Explains why the testimony write decision grew from two outcomes to four, and how nothing_qualified? tells 'nothing qualifies' apart from 'nothing worked'."
status: agent-extracted
related: []
---
# Why the testimony write decision has four outcomes

<!-- vale Vale.Spelling = NO -->

`FetchHearingsService#testimony_write_decision` decides what a hearing-fetch
run may say about a bill's testimony — see
`docs/reference/testimony-write-decision-outcomes.md` for the four
outcomes themselves. This document explains why the logic grew a third and
a fourth way to reach `:retain_with_notice`, and why `#nothing_qualified?`
draws the line where it does.

## Extracted from an if/elsif chain

The decision logic was pulled out of `#persist_testimony!` so the four
outcomes could be enumerated in one place, instead of being spread across
an if/elsif chain whose arms each carried a paragraph of reasoning.

## The third way into `:retain_with_notice`

`#sweep_incomplete?` cuts across the count-based split between the other
outcomes instead of dividing it cleanly, so it shows up as an extra `or`
condition on the way into `:retain_with_notice`, and gets subtracted out of
`#nothing_qualified?`'s definition. Both changes were needed together:
without the first, an incomplete sweep that still produced a positive
discovery count would fall through to `:none` and rewrite the admin list to
empty, while the stored column kept its text — exactly the bug
`:retain_with_notice` was added to fix in the first place.

## The fourth way

A fourth way guards the same hole from the other side: candidates were in
hand, but none of them ended up contributing text. See the comment at the
check in the source for the detail.

## `#nothing_qualified?`: distinguishing "nothing qualifies" from "nothing worked"

`#nothing_qualified?` answers "nothing composed because NOTHING QUALIFIES,"
as distinct from "nothing composed because nothing WORKED." Only the first
is solid enough grounds to justify deleting previously stored evidence
(the `:retract` outcome).

The thing that tells the two apart is already available: discovery FOUND
attachments — `@discovery_found` counts them before any filtering runs —
and the `.pdf` check plus `Testimony::AttachmentClassifier` kept none of
them. That combination means discovery ran, saw the bill's real attachment
list, and judged every single one of them to be something other than
testimony.

The check is deliberately cautious in two other directions, plus a third
direction added later:

- **`@discovery_found == 0` is ambiguous.** It describes both a bill that
  genuinely has no attachments and a Legistar outage, because
  `#fetch_matter_attachments` and `#fetch_event_item_matter_attachments`
  both fall back to an empty list by design when their upstream call
  fails. The stored column is kept in this case rather than retracted.
- **Records present but empty-handed is a passing failure, not proof of
  nothing.** If downloads failed, or `mutool` found no text layer in a
  scanned PDF, the testimony still exists — this run simply could not read
  it. The stored column is kept.
- **A third direction the original two checks did not cover: an
  incomplete sweep.** The two checks above are both counts, and a count
  cannot express "the sweep that produced it was only partial."
  `@discovery_found` goes positive as soon as the MATTER-level attachment
  collection returns anything at all, so a matter whose attachments all
  get re-classified as bill text could reach `:retract` even when a whole
  hearing event's attachments were never actually read. `:retract` deletes
  `extracted_testimony` AND marks every draft organization position as
  evidence-retracted — a confident, destructive claim built on evidence
  this run never actually saw. `#sweep_incomplete?` closes that gap.

## Inside `:replace`: losing one attachment while composing something is still evidence loss

`#testimony_write_decision` answers `:replace` for ANY non-empty
composition, so a run that loses attachment A — because it was
re-classified as bill text, which drops it from the candidate set entirely
(see `docs/explanation/bill-text-filter-history.md`) — while attachment B
still composes, wrote strictly less evidence even though the bill-level
check only asks whether testimony is MISSING, and it is present. The Bill
Creator card's Approve button reads `evidence_retracted_at` and whether
testimony exists, not whether the summary is stale, so moving
`testimony_fetched_at` is not by itself a signal to that button — the
`evidence_retracted_at` flag from `#evidence_withdrawn?` is what actually
gates Approve. `provisioning.testimony_attachments` (the previous run's
list) has to be read before it gets overwritten with this run's, so
`#evidence_withdrawn?` can compare the two.

## Inside `:retract`: why the column is cleared AND the drafts built on it are flagged

Keeping the previous testimony would be right if a re-fetch failed for a
PASSING reason, and wrong for the case the testimony filter created: a bill
whose attachments are all correctly re-classified as bill text composes to
`""`, so an old `extracted_testimony` — measured at 87% bill text before
the filter existed (see `docs/explanation/bill-text-filter-history.md`) —
would otherwise sit in the column forever, keep feeding
`BillPositionsPromptBuilder#combined_testimony`, and contradict an admin
list that had already been rewritten to show zero candidates. The screen
built to explain missing testimony cannot disagree with the column it
explains, so `:retract` clears `extracted_testimony`.

`testimony_fetched_at` moves when the column is cleared for the same reason
it moves when the text changes: the composed value CHANGED, and marking
the summary stale is exactly the signal the operator needs — the existing
summary was built on evidence now known to be wrong.

Clearing the evidence and leaving the conclusions drawn from it was only
half a fix. Draft organization positions written before the testimony
filter existed were generated from the bill DIFF, and nothing on this path
used to retire them — the job's testimony check had no `else` branch, the
positions rescue kept them, and no migration touched the column — so they
survived every regeneration and stayed approvable into PUBLIC
`OrganizationBillPosition` rows stating a named organization's stance. That
was precisely the credibility risk this whole area exists to prevent,
reached through the very clean-up path the spec prescribes. The fix flags
rather than deletes: `draft_org_positions` is the operator's triage state,
so `ApproveOrgPositionService` refuses a flagged draft, the Bill Creator
card says why, and Reject or regenerate are the two ways out. Both the
clearing and the flagging are one assignment each, saved by the same
`save!` as the columns they describe, so "the evidence is gone" and "the
conclusions are flagged" cannot disagree.
