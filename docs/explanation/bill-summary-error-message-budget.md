---
mode: explanation
summary: "Explains the shared error-message length budget in GenerateBillSummaryJob: why it exists, how MAX_POSITIONS_FAILED_REASON_LENGTH is derived, and the truncation rules that keep a composed message intact."
status: agent-extracted
related: [docs/explanation/bill-summary-nothing-to-generate-settlement.md]
---
<!-- vale Vale.Spelling = NO -->

# The error-message length budget in GenerateBillSummaryJob

## Why the cap exists

`MAX_GENERATION_ERROR_LENGTH` (500) caps the stored error text. A
misbehaving adapter could return a multi-megabyte message, which would
bloat the DB row and the admin page's Inertia payload.

## Why `NO_SOURCE_TEXT_POSITIONS_FAILED_ERROR` exists at all

On a testimony-only bill (no bill text at all), the positions call is the
ONLY paid call the run makes. If that call fails, the row ends up holding
nothing — no summary, no positions — and the default success-flavored
reason ("The organization positions below were generated from its
testimony and are unaffected") would be a false statement: the one
operator-visible output of the run, claiming positions exist when the
call that would have produced them just failed. The real reason (a rate
limit, a schema break) would otherwise survive only in the log, invisible
to the operator reading the row. `NO_SOURCE_TEXT_POSITIONS_FAILED_ERROR`
is the template that names the actual failure instead.

## Deriving MAX_POSITIONS_FAILED_REASON_LENGTH from the template

`MAX_POSITIONS_FAILED_REASON_LENGTH` is the room an adapter message has
inside the cap, once `NO_SOURCE_TEXT_POSITIONS_FAILED_ERROR`'s own words
are counted. `%{reason}` sits in the MIDDLE of that template, so capping
the composed string cuts from the right — a reason longer than this
budget throws away the instruction the constant was written to deliver,
and leaves the message ending mid-word inside the adapter's text. Reasons
that long are ordinary: `Llm::SchemaValidator` joins every failing field
path into one uncapped string, and some `ClaudeAdapter` messages already
measure within a character or two of this number.

It is SUBTRACTED from the template rather than hand-counted. A
hand-counted prefix length is how a sibling site (the positions call's own
rescue, below) came out one character over, and it re-breaks silently
every time the wording changes.

## POSITIONS_EVIDENCE_WITHDRAWN_REASON has to fit two homes

`POSITIONS_EVIDENCE_WITHDRAWN_REASON` is written straight to
`generation_error` under `POSITIONS_DISCARDED_PREFIX`, and also carried
into `NO_SOURCE_TEXT_POSITIONS_FAILED_ERROR`'s `%{reason}` slot on a
testimony-only bill — so it is worded to read as a sentence in both.

It ALSO HAS TO FIT. The carried home trims the reason to
`MAX_POSITIONS_FAILED_REASON_LENGTH`, and this string used to run 236
characters against that 226-character budget — so on EVERY run that
reached it the operator read a message that stopped at "then gene…",
losing the one sentence naming what they can do about it. Both operands
are constants, so nothing about it was data-dependent. A spec pinning that
the example text "fits the reason slot it is carried into" is what stops
a reword putting it back over.

The wording says "changed," not "removed": the persist declines whenever
the testimony this run read is no longer the testimony on the row, and
that includes evidence being ADDED by a concurrent fetch — rarer than a
withdrawal and the same answer either way, since the drafts were drawn
from a snapshot that has gone. Naming the wider case keeps the sentence
true on every path that can store it.

## Trimming a reason without breaking the sentence after it

`#no_source_text_message` trims a positions-failure reason to what
`NO_SOURCE_TEXT_POSITIONS_FAILED_ERROR`'s template leaves it, so the
sentence AFTER `%{reason}` — the one telling the operator what Retry will
do — survives every reason length. `String#truncate` marks the cut, so a
reason that stops abruptly reads as trimmed rather than as a broken
adapter message, and the outer slice stays as the ceiling the column and
the admin payload depend on.

The template supplies the full stop after the slot, so a reason that
brings its own would end the sentence "generate again.." — which was
hidden while `POSITIONS_EVIDENCE_WITHDRAWN_REASON` was being cut mid-word
and became visible the moment it fit. The trailing period is
dropped from the reason here rather than from the constant, because this
is the one place the two are joined, and it covers an adapter message
that ends in a period too. A truncated reason ends in "…", which this
leaves alone.

## Why a spec pins `MAX_POSITIONS_FAILED_REASON_LENGTH >= 200`

If the template's own words ever passed the cap, the budget would go
NEGATIVE — and `String#truncate` does not raise on a negative limit: it
takes the truncating branch, `self[0, -n - 1]` is `nil`, and the result is
a bare `"…"`. The composed message would then be the whole template, past
the cap, with the outer slice cutting from the right again — the exact
fault the constant was added to close.

The floor is pinned at 200 rather than 0, because a budget above zero is
not the requirement; room for a real adapter message is. Two
`ClaudeAdapter` messages already measure within a character or two of the
current 226, so a template that grows by more than roughly 26 characters
starves the reason this message exists to carry, and a spec forces the
author to say so out loud rather than let it drift silently.

A second spec pins that `NO_SOURCE_TEXT_POSITIONS_FAILED_ERROR` carries
exactly one `%{reason}` placeholder, which is what the subtraction
measures: `String#sub` replaces ONE occurrence while `format` substitutes
every one, so a second `%{reason}` would be counted as fixed text (the
budget would read 9 characters short) and still be filled in twice,
pushing the composed message to roughly `fixed + 2 × budget` — over the
cap, and cut from the right again.

## Slicing the composed string, not a hand-counted prefix

The positions call's own rescue caps its `generation_error` write by
slicing the COMPOSED string (prefix + error message), not by subtracting
a hand-counted prefix length from the cap: subtracting got the count
wrong once (the prefix was 46 characters, not 45, so the result came out
at 501) and silently re-breaks every time the wording changes. The inner
slice on the error message only keeps an adapter's multi-megabyte message
from being built up in the first place.
