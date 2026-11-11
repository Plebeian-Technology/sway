---
mode: explanation
summary: "Explains the two mechanisms that make an auto-included pipeline stage do less work than the same stage ticked by hand, and why fetch_law is the one stage exempt from the frontend's reduced-work warning."
status: agent-extracted
related: []
---

# Why an auto-included stage does less work

The stage picker in the admin Bill Creator tells the operator, before a run
starts, which of the stages being added on their behalf will do LESS than
the same stage ticked by hand. That sentence is only worth printing if it is
true, and what makes it true lives in `RunLegislationPipelineJob`, not in
the browser. `spec/integration/stage_deps_sync_spec.rb` derives both
mechanisms from the job rather than restating them, so the frontend's
`REDUCED_WHEN_AUTO_INCLUDED` list can never say something the job does not
actually do.

## The two mechanisms

- `fetch_bills` takes a `mode` kwarg: `:discover` when the operator chose
  it, `:backfill_missing` when it was added on their behalf. In backfill
  mode it stops discovering new bills. It still asks for a bill already in
  the run by name when that bill has nothing saved — a repair, not a
  discovery.
- Every `BILL_LEVEL` stage turns on an artifact-aware skip gate when added,
  so it passes over bills that already have its output.

## The one stage exempt from the warning

`fetch_law` is in neither group: no mode, no per-bill loop, identical work
whether the operator chose it or the job added it. If it ever appeared in
the TypeScript `REDUCED_WHEN_AUTO_INCLUDED` list, the picker would tell an
operator their law fetch had been cut down when it had not.

## PipelineStageSelector notes

Of the stages being added for the operator, which ones will do less than
they would if the operator had ticked them. Named one by one rather than
covered by a blanket sentence, because fetch-law is added on the same
terms and does exactly the same work either way.

A stage added for you does LESS than the same stage
you tick, and until now nothing said so before the
run started. Both carried the same name in this
same box, so a run that skipped everything looked
exactly like a run that had nothing to do.

## Why the stage-selection buttons are Select all / Clear all, not one tick-all box

Replaces the WHOLE selection in one call. Select all and Clear all use
this rather than calling onToggleStage seven times — see the comment on
those buttons for why that difference matters.

TWO BUTTONS RATHER THAN ONE TICK-ALL BOX. There are three
states — none, some, all — and a box that only knows on and
off has to misreport the middle one. Two buttons say what
they do, and each greys out when it would change nothing, so
the three states are readable without a half-ticked glyph
nobody agrees on the meaning of: both live means some are
ticked. The count spells it out besides.

NEITHER ASKS FOR CONFIRMATION, on purpose. This card only
CHOOSES stages; Run is what starts them, and that is where
the cost is explained and where the prerequisite warning
already appears. A confirm here would be confirming the
wrong action.

## Why the "Stages to run" card's selected count is derived from STAGES, not selectedStages.length

Counted against the real stage list rather than reading
selectedStages.length, so a stale or unknown key left in the address
cannot make six stages look like seven.

## Why "Download missing assets" is disabled when both fetch stages are checked

The "Stages to run" card: seven stage checkboxes, a notice listing stages
that will be pulled in automatically, a warning about bills that would fail
for want of earlier data, and the "Download missing assets" toggle.

That toggle took the place of an older "Pull fresh data from Legistar"
checkbox. It is greyed out exactly when both fetch stages — Fetch bills and
Fetch hearings — are checked, and that is worked out while rendering, with no
useEffect. The server behaves the same way: whatever the greyed-out box looks
like, the controller decides for itself that downloading missing assets is on
when the request comes in.

Worked out while rendering. With both fetch stages checked, every piece
of upstream data is produced again, so there are no gaps left to fill and
the toggle has nothing to do.

With both fetch stages checked, the server treats this setting as on no
matter what was stored, so the box shows as ticked even while greyed out.

## Why the auto-included stage chips are comma-separated with a screen-reader-only comma

A comma sits between the chips, hidden from sight
but not from screen readers. Screen readers and
copy-paste both take the plain text of this block,
where the visual spacing does not exist, so without
the commas it came out as "Fetch lawExtract textParse
sections" instead of "Fetch law, Extract text, Parse
sections".

Testing reported this list reading as "Fetch lawExtract textParse
sections", with nothing between the names. The chips are spaced apart on
screen (`flex flex-wrap gap-2`), but the plain text of the alert — what a
screen reader reads out and what copy-paste picks up — carries no such
spacing, so the names ran together. A comma hidden from sight now sits
between the badges, so both come out as "Fetch law, Extract text, Parse
sections".

## Why the prerequisite-violation warning renders before the run starts

A warning shown BEFORE the run starts, so the operator can see
which bills would fail for want of earlier data. The wording
("will FAIL") is the agreed copy, kept word for word.
