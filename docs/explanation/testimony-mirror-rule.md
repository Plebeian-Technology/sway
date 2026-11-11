---
mode: explanation
summary: "Explains the rule that testimony_attachments must always describe exactly what is in extracted_testimony, and how each writer keeps it true."
status: agent-extracted
related: []
---
# The testimony mirror rule

<!-- vale Vale.Spelling = NO -->

`BillLlmProvisioning` owns two columns, `testimony_attachments` and
`extracted_testimony`, and everything built on top of them depends on a rule
that ties the two together.

## The rule

The stored `testimony_attachments` list DESCRIBES the stored
`extracted_testimony`. The attachments whose text is inside the composed
`extracted_testimony` are exactly the rows whose `extraction_status` is one of
`FetchHearingsService`'s contributing values ("succeeded",
"reused_prior_run"). Every other row explains itself and contributes nothing
to the composed text.

## Why it matters

`testimony_attachments` began as a display artifact and became load-bearing
for the publish gate: four different discriminators, catalogued in
[Who marks a draft's evidence retracted](evidence-retraction.md), each answer
"did the evidence change" by reading one or both of these columns. Each of
those discriminators is correct only while the mirror really describes the
composition.

## How the rule is kept

The two columns are written together, in one save, by one writer:
`FetchHearingsService#persist_testimony!`. Each of its outcomes keeps the
rule:

- `:replace` writes both columns from the current run.
- `:retract` clears the text and leaves no contributing row.
- `:retain_with_notice` keeps the text AND carries the previous contributing
  rows forward, re-labelled `"reused_prior_run"`.
- `:none` stands only while the kept mirror still describes the kept text —
  a run whose own records contribute nothing routes to
  `:retain_with_notice` instead, so the carried-forward census is never
  erased under kept text.

## Known tolerances

Two tolerances are accepted on purpose, and both err toward NOT flagging a
withdrawal:

- Text cut at the composed-size cap leaves rows past the cut still reading
  `"succeeded"`.
- A sidecar whose text CHANGED still counts as contributing (see
  `FetchHearingsService#evidence_withdrawn?`).

## The obligation this places on future code

Anything that writes either column anywhere else must keep this rule, or the
publish gate built on these columns gives wrong answers.

## Why carried-forward rows are re-labelled `reused_prior_run`, not `succeeded`

Before `#carried_forward_mirror_entries` existed, `:retain_with_notice`
wrote a status list containing ONLY a made-up notice, which wiped out the
record the next `:replace` needs in order to spot a withdrawal — one
passing Legistar outage therefore disabled withdrawal detection for that
bill forever. The original objection to keeping the previous
list was right, and it is answered rather than ignored here: repeating
`"succeeded"` on a carried-forward row would claim a download and an
extraction THIS run never did. `EXTRACTION_STATUS_REUSED` already means
exactly "this text came from an earlier run," already counts as
contributing, and already renders in its own list on the admin screen — so
the record survives across runs and the display is more honest than the
single vague notice it replaces.

## Why the carried-forward row wins over this run's row, on overlap

`:retain_with_notice` carries the previous run's contributing entries
forward (re-labelled `reused_prior_run`) via
`#carried_forward_mirror_entries`, and those carried-forward entries are
placed FIRST in the list, ahead of this run's own rows for the same
attachment where the two overlap. The overlap happens because
`@content_denied_records` can include an attachment that is also in the
carried-forward set — the fourth route into `:retain_with_notice`
(candidates in hand, none contributing) arrives with a
non-empty record list, and routes 1-3 can carry a denied record for an
attachment that is also in the stored mirror. Two rows would then render in
two different alerts about one document: "carried over … it does not need
to be supplied again" beside "attachment issue … paste the testimony text
below".

The carried-forward row wins, for three reasons that all say the same
thing — the list describes the TEXT THAT IS STORED, not what this run
attempted:

1. **The mirror rule itself.** `:retain_with_notice` KEEPS
   `extracted_testimony`, so the attachment's text really is inside the
   composition, and a contributing status is the only honest label for it.
   Every row this run produced is non-contributing by construction on the
   routes where the overlap happens.
2. **The admin screen.** `extraction_failed` and `content_denied` both file
   the document under "paste the testimony text into Supplemental
   testimony below" — for a document whose text is already in
   `extracted_testimony` and already in
   `BillPositionsPromptBuilder#combined_testimony`. An operator who follows
   that instruction feeds the positions call the same words twice, which
   over-weights one organization in a list that becomes public
   `OrganizationBillPosition` rows. The `content_denied` wording is
   outright false in that overlap case: it says the text is left out of the
   testimony feeding the summary, and it is not.
3. **Withdrawal detection.** `#evidence_withdrawn?` subtracts THIS run's
   contributing entries from the PREVIOUS run's, so an attachment that is
   non-contributing in the stored mirror is not in `previous` and can never
   turn up in the difference. Downgrading a carried-forward row to this
   run's non-contributing status would mean the next `:replace` that drops
   that attachment flags nothing, Approve stays enabled, and a draft whose
   evidence is gone can be published — the same hole, reached from the
   other side.

What is lost by dropping this run's row on overlap: the `error` explaining
why this run could not re-extract. The surviving row states the thing the
operator has to act on — the text is in hand — and re-labelling this run's
row while merging its error would say the same thing at more cost.

The merge is keyed on `attachment_id`, never on the display label
(`filename`), because Legistar does not keep names unique. A carried-forward
row written before the id key existed has no id and so removes nothing on
merge — the same false-alarm-avoiding direction `#comparable_by_id?` takes
for the same reason (see
`docs/explanation/evidence-withdrawal-detection.md`).

## Why `:retain_with_notice` writes a made-up row instead of an empty or unchanged list

Before `:retain_with_notice` existed as its own outcome, the admin list was
written unconditionally regardless of outcome, so a run where discovery
came back with nothing for some reason OTHER than reclassification
rewrote the list to empty while the column kept an earlier run's text. An
empty list renders as nothing at all
(`LlmSummaryTestimonyAttachmentWarning` returns null when the failed list
is empty), so the admin saw no attachments AND no warning while
`has_testimony` stayed true and the positions prompt was still being fed
that text — the same rule the `:retract` branch enforces, applied in the
direction it did not originally consider: the screen built to explain
missing testimony cannot disagree with the column it explains.

Keeping the previous list unchanged was the other option considered, and
it is worse: it would claim per-attachment statuses THIS run never
established. A made-up entry (`#truncation_mirror_entry` set the
precedent) states only what is actually known.

## Why `:retain_with_notice` also fires when every candidate produced no text

`#testimony_write_decision` routes to `:retain_with_notice` — rather than
falling through to `:none` — when records exist but none of them has a
`CONTRIBUTING_EXTRACTION_STATUSES` status: every download or extraction
failed and no sidecar survived (upstream rotated its attachment ids, say,
and the new ones would not download). The kept column still feeds the
positions prompt, so falling through to `:none` here would rewrite the
mirror from records that contribute nothing: the admin list would claim no
attachment feeds the text, and the carried-forward census the NEXT run's
withdrawal check compares against would be erased — one passing failure
would disable withdrawal detection for the bill forever, the exact hole the
carried-forward entries above exist to close. The mirror must keep
describing the composition, so this case takes the same treatment as the
other `:retain_with_notice` routes.

The one arm that stays `:none` even though a record claims a contributing
status: `#attachment_txt_present?` and `#compose_testimony_from_disk` are
two reads of the same sidecar path at different times, and the file can be
truncated, replaced, or removed in between — the same gap
`@content_unreadable_ids` exists for, taken from the other direction. A
rare arm, but not a dead one, and `:none` is the honest answer for it: since
nothing was built and the stored column stands unchallenged.

## Why made-up rows can never be mistaken for a withdrawn attachment

`#contributing_entries` filters `testimony_attachments` down to the rows
whose `extraction_status` is one of `CONTRIBUTING_EXTRACTION_STATUSES`,
before `#evidence_withdrawn?` compares two runs' lists. That same status
check is what keeps every MADE-UP row out of the comparison on both sides:
`#truncation_mirror_entry`, `#retained_testimony_mirror_entry`, and the two
"not read this run" entries all carry `EXTRACTION_STATUS_NOT_ATTEMPTED`, so
none of them can be mistaken for a real attachment that went away — they
name no attachment and must not look like one. `#contributing_entries` also
checks the shape of each element (`entry.is_a?(::Hash)`) because
`testimony_attachments` is a JSON column older than this set of keys.

## Why each made-up mirror row has its own wording

Several `FetchHearingsService` methods synthesize a mirror row describing
something the run could not establish, rather than describing a real
attachment: `#retained_testimony_mirror_entry`,
`#no_contributing_candidates_mirror_entry`,
`#unswept_events_mirror_entry`, and `#unswept_collections_mirror_entry`
(selected between by `#incomplete_sweep_mirror_entry`). Each has its own
wording rather than sharing one string, because the operator's next move
differs by case:

- **`#retained_testimony_mirror_entry`** — Legistar returned no attachments
  at all this run. Written only when an earlier run's testimony is
  actually being kept; a bill that genuinely has no attachments and no
  kept text has no contradiction to explain, and a permanent warning row on
  every such bill would be noise. Says: re-run to confirm it is still
  upstream.
- **`#no_contributing_candidates_mirror_entry`** — candidates were
  discovered but none contributed text. It cannot share the row above's
  wording, because that row asserts nothing was downloaded or extracted,
  and this route arrives with a non-empty record list whose rows are on the
  same screen, each carrying its own real reason — the summary row would
  contradict the detail rows beneath it. It counts over the UNION of
  `records` and `@content_denied_records`, not just `records`, because a
  content-denied document downloaded and extracted perfectly well before
  the model rejected it, so `records.length` alone understates the
  attachments this run actually saw. Says: re-run, or paste the testimony
  by hand.
- **`#unswept_events_mirror_entry`** and **`#unswept_collections_mirror_entry`**
  — the sweep of the matter's events or collections was incomplete. Events are picked over collections when both apply
  (`#incomplete_sweep_mirror_entry`'s ordering), because an event id is
  something the operator can paste into Legistar to check, while a
  collection is only a URL they can re-run — most actionable first. The
  events version names the specific event ids; the collections version
  names the endpoint route. Both note that a Legistar sub-resource answers
  `200 []` for a parent that no longer resolves, so an empty result from an
  unswept event or collection proves nothing (see
  `docs/explanation/legistar-client-design.md` for that general Legistar
  behavior).
