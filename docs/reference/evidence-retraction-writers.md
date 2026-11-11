---
mode: reference
summary: "Lists the five writers that can stamp a draft's evidence as retracted and what condition triggers each one."
status: agent-extracted
related: [docs/explanation/evidence-retraction.md, docs/explanation/supplemental-testimony-write-rule.md]
---
<!-- vale Vale.Spelling = NO -->

# Who marks a draft's evidence retracted

`BillLlmProvisioning.drafts_with_evidence_retracted` stamps a draft when its
evidence is confirmed gone. See
[Marking a draft's evidence as retracted](../explanation/evidence-retraction.md)
for the rule this table applies and the reasoning behind it. This document
lists every writer that can trigger the stamp.

Five writers exist. Four ask a question first; the fifth is the act itself,
so it has nothing to ask.

## FetchHearingsService#persist_testimony!, its :retract branch

Fires when the run put together no testimony AND the search proved nothing
qualifies (`#nothing_qualified?`: it saw the bill's real attachment list and
the classifier kept none of it).

The `:retain_with_notice` branch is deliberately NOT a caller: there the
search itself came back empty, and an outage at Legistar looks exactly like
a bill with no attachments, so the evidence may be perfectly good.

## FetchHearingsService#persist_testimony!, its :replace branch

Handles the same total withdrawal as the `:retract` branch, but one
attachment at a time. A run that decides attachment A is really bill text
drops A from the pool entirely while B still contributes, so the stored
column is not empty, is different, and now rests on strictly less evidence
than the drafts were drawn from.

The test is `#evidence_withdrawn?`: it compares the per-attachment status
records and stamps when an attachment whose text went into the STORED
testimony no longer does. It is not the "does the new text contain the old"
test used by `SupplementalTestimonyWrite.evidence_retraction_attrs` below —
see that entry for why.

## SupplementalTestimonyWrite.evidence_retraction_attrs

Fires on a paste that REPLACES the stored testimony rather than adding to
it, spotted with `value.include?(stored)`.

That test is right for ONE string an operator pasted, and wrong for
`extracted_testimony`, which is built by joining attachments together: a
containment check cannot see one member LEAVE a joined value, and it gets
the answer wrong on an insertion in the middle (`"A\n\nB\n\nC"` does not
contain `"A\n\nC"`) and on re-truncation. The joined column's writer above
needs to identify individual attachments, which a single pasted string
cannot offer. The two columns genuinely need different tests for this one
rule.

This is the replacement case: a replacement destroys the evidence behind
drafts that already exist, exactly as completely as a clear does — and none
of the other controls can see it. `ApproveOrgPositionService`'s bill-level
gate asks whether testimony is ABSENT, and after a replacement it is
present, so nothing is refused. `FetchHearingsService#persist_testimony!`'s
`:retract` branch above never runs on this path. And there is not even a
stale chip: `BillLlmProvisioning#stale?` keys on `testimony_fetched_at`,
which only `FetchHearingsService` writes. The ordinary operator sequence —
paste the wrong bill's testimony, generate, notice, replace it with the
right text, approve the cards still on screen — therefore publishes a
public `OrganizationBillPosition` asserting a named organization's stance,
drawn from testimony that was never about the bill, without a single guard
firing. A clear stamps too (see the entry above) — the two
paths now agree, because they are the same act (the evidence these
conclusions rest on is gone) reached two ways. What is still specific to
this path is the discriminator: a clear is unconditional, a write has to
decide whether it removed anything.

The discriminator is "does not contain," not "differs," because an operator
APPENDING to their paste has withdrawn nothing — every word the drafts were
drawn from is still on the row — and the mark's own meaning is "the
testimony these conclusions were drawn from was withdrawn." Stamping there
would assert something false about those drafts and would cost a
regeneration to undo. Any other edit removes text the drafts may rest on,
and the testimony gate on draft positions fails closed on that. A FIRST paste is not a replacement: there
was no stored value to destroy, so `#evidence_retraction_attrs` returns `{}`
when `stored` is blank.

The stamp rides in the SAME attribute hash as the column it is about, so it
lands in the caller's single `update!` — "the evidence changed" and "the
conclusions are marked" cannot disagree. Same construction, and the same
reason for it, as `FetchHearingsService#persist_testimony!`'s `:retract`
arm above.

## SupplementalTestimonyWrite.clear_retraction_attrs

The CLEAR, and the one writer with NO comparison in it: it stamps whenever
drafts exist. That is not a missing test. A clear destroys the pasted
column outright, so "is the evidence gone" is settled by the act; there is
no new value to compare a stored one against. Its sibling above needs a
discriminator precisely because a write might have ADDED rather than
removed.

A clear used to stamp nothing, on the argument that pasting again restores
approval with nothing lost — exactly what was found to be untrue: on
a bill that ALSO has hearing testimony the bill-level check never refuses,
so a draft whose evidence had been deleted stayed publishable. Nothing can
prove a later paste is what was removed, so the mark survives one;
Regenerate and Reject are the two ways out.

That old argument also assumed the deferred decision — "was the re-paste
the same text?" — would get settled later. It never does:
`#evidence_retraction_attrs` cannot check that, because by the time a
re-paste arrives `stored` is already `nil`, so it takes the "a first paste
is not a replacement" branch above and stamps nothing. Clear, then paste
DIFFERENT testimony, and Approve publishes a public claim about a named
organization drawn from the wrong bill's evidence — through the very button
built for "I pasted the wrong bill's testimony".

The cost is real and is now paid up front rather than discovered: an
operator who clears and re-enters identical text must regenerate. That is
why the Clear affordance warns before it fires
(`BillCreatorLlmSummary#handleClearSupplemental`) — the user's call, not a
silent trade.

## The data migration

`db/data/20260726000002_retire_untestified_draft_org_positions` marks
drafts on a row with no testimony of either kind — the same finding reached
by looking at history rather than at a write.

## Summary

Five writers: four comparisons and one unconditional stamp — a composed
string, a mirror-to-mirror set difference, a string containment test, a
two-column blank check, and the clear.
