---
lat:
  mode: explanation
---
# Approving a campaign from a testimony draft

The clean-testimony stage groups letters into campaign drafts, and an operator turns one of those drafts into a published `Campaign`. The approval has to say which draft it came from, because several drafts on one bill can carry the same name.

## A campaign belongs to one bill

Uniqueness is scoped to the bill, so the same campaign name on two different bills is two campaigns.

The earlier model scoped it to the locale, and approving the same name on a
second bill matched the first bill's row and rewrote its stance — the first bill
silently lost its own position. A campaign is advocacy about one bill, so
bill-scoped matching is what the model actually means.

## A draft's identity is its content, not its position

A draft is named by the hash of what it holds, and the position it happens to occupy in the array is not part of that identity.

The approval used to require an index as well and refused unless it pointed at
the named draft, which made the array's order load-bearing. A re-run that leaves
a draft's own text untouched can still move it, and that turned a correct
approval into a "this draft has changed" refusal.

## Approving over a name already taken is reported, not refused

A second draft approved under a name a campaign already holds still writes, and the result says that it replaced a decision made from a different draft.

Refusing would wall an operator on a bill whose single campaign is split across
several drafts, which is an ordinary outcome of grouping rather than a mistake.
What was wrong before was the silence: a campaign carried no record of which
draft it was approved from, so re-approving one draft and approving a second
under the same name were indistinguishable — both overwrote stance, summary and
counts, and both reported plain success.

## An approved campaign is sent back to the page that approved it

The approved campaign travels back to the Bill Creator as a prop of its own, keyed to the draft it came from.

It used to be write-only — no association, no serializer, no prop — so the page
rebuilt its draft cards from the cleaned artifact alone and the card looked
exactly as it had before, through the redirect and through a reload. The prop
that carries the candidate organizations is rebuilt on every render of that tab,
which polls every few seconds, so its cost has to stay flat as approved
campaigns accumulate on the bill.

## An organization link carries the decision that made it

A campaign's organization arrives together with the decision that put it there, and setting the link alone is refused.

A link nobody recorded a decision for is exactly the ambiguity the second
approval step exists to remove. A campaign nobody has been asked about reads as
undecided rather than as unlinked, so the serializer ships the link and lets
nil stay nil instead of flattening it into a decision.

## What a decision log entry has to identify

An entry in the decision log names the letter position the decision was made from, not an index the surface never sends.

The claimed-affiliation path is the one approval whose published organization
name is typed by an operator out of a letter's own text, and it was the only one
recording nothing identifying at all: the logged id was built from an index that
card deliberately never sends, so it was always nil. The letter position was
available the whole time.
