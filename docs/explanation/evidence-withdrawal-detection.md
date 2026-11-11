---
mode: explanation
summary: "Explains why testimony evidence withdrawal is detected with a per-attachment identity check instead of a substring comparison."
status: agent-extracted
related: []
---

# How evidence withdrawal is detected across hearing-fetch runs

<!-- vale Vale.Spelling = NO -->

`FetchHearingsService#evidence_withdrawn?` answers one question: did an
attachment whose text WAS part of the stored testimony stop contributing to
it? The `:replace` branch of `#persist_testimony!` uses the answer to
decide whether evidence was taken away from a bill's testimony. This
document explains why the check works the way it does, and is deliberately
NOT the same test another writer of this column uses.

## Why a substring check does not work here

`SupplementalTestimonyWrite.evidence_retraction_attrs` tells a replacement
from an addition using `value.include?(stored)`. That comparison is
correct for one operator-pasted string, but wrong for this column, because
`#compose_testimony_from_disk` builds its value by walking the attachment
records in order and joining their texts with a blank line between them.

Walking through what that does to a substring check:

- Stored `[A, C]`, composed `[A, B, C]`: `include?("A\n\nC")` is FALSE, even
  though a middle insertion withdrew nothing at all.
- Re-truncation past `MAX_COMPOSED_TESTIMONY_CHARS` breaks the same check
  the same way.

Flagging a draft when nothing was actually withdrawn is not a harmless
false alarm: it claims the evidence a draft rests on was pulled when it was
not, disables the Approve action on that draft, and costs a paid
regeneration to clear. The comparison is therefore done PER-ATTACHMENT and
works on sets, not on a substring of the joined text — a substring test
cannot see one member leaving a joined string, and an attachment that gets
re-classified as bill text leaves the candidate set entirely rather than
changing its status in place.

## Three limits, written down rather than left to be rediscovered

1. **One key, not two.** Identity is `attachment_id`, and BOTH sides being
   compared must carry it — `#attachment_status_mirror` writes it on every
   row it builds from a record, and `#comparable_by_id?` decides whether a
   pair can be compared at all. When either side lacks it, the check
   reports no withdrawal rather than falling back to a second key.

   `filename` used to be that second key, and it could not do the job. It
   holds a DISPLAY LABEL — `#attachment_status_mirror` writes
   `record["name"].presence || record["filename"]` — not a unique identity,
   and what it held actually CHANGED partway through this feature's
   development: the column first shipped carrying the raw upstream
   name, a later commit switched it to the display name, and
   `attachment_id` was added later still. A mirror stored during
   that first window therefore matches no label a later run writes, so
   comparing on `filename` reported every draft as withdrawn — exactly the
   false alarm the id-based fallback was added to prevent. A stored mirror
   with no id now simply goes unflagged for one run instead.

2. **Losing text to the size cap is invisible to this check.** When
   composition hits `MAX_COMPOSED_TESTIMONY_CHARS`, the loop stops, so
   records after the cut contribute no text to the final column even
   though their status entries still read "succeeded." The check errs
   toward NOT flagging in this case — see the cost of a false flag above —
   and the cut itself is already visible elsewhere, in the column and on
   the status list.

3. **An attachment whose SIDECAR TEXT CHANGED is still counted as
   contributing.** The question this check asks is "did an attachment stop
   contributing," not "is the text identical to before." Re-extracting the
   same attachment to different text means the upstream document was
   revised, not that evidence was pulled from the bill.

## When this check does not run at all

A run that composed nothing never reaches this check at all — that
outcome is `:retract`, `:retain_with_notice`, or `:none` (see
`docs/explanation/testimony-write-decision.md`). Neither does a run whose
composed value is unchanged from before: if the stored column did not
move, no evidence left it.
