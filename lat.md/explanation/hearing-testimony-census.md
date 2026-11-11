---
lat:
  mode: explanation
---
# What a hearings fetch can conclude

A hearings run reads a bill's hearings from Legistar and rewrites what Sway believes about the testimony attached to them, so the difference between "there is none" and "this run could not see it" decides whether real evidence is thrown away.

## Event ids come only from a matter's histories

`Matters/<id>/Histories` is the only endpoint that yields hearing event ids, and naming a matter's histories also asserts the matter exists.

`Matters/<id>/Events` reads like the obvious route and is not a real one: a live
GET returns 404. The old code read that 404 as "this bill had no hearings" and
wrote an empty array for bills that had several. A probe over one matter shows
why the two collections are both needed and neither is sufficient — Attachments
alone returns 26 PDFs, so the union of the two can be non-empty while one half
is silently failing.

## A run that could not read something is not authoritative

A fetch that fails to read part of the census marks itself non-authoritative instead of reporting what it managed to read as the whole answer.

The failures are indistinguishable from an honest empty result at every level.
A bogus event id looks exactly like an event with no agenda items, and an
`EventItems` call that returns a 2xx body which is not an array degrades to an
empty list just as a rescue does. Raising instead would throw away the matter's
other real events, so the run continues and records that it is incomplete —
which is what stops the next comparison from reading a short list as a
withdrawal.

## An error names the stage that writes the file it wanted

A missing artifact is reported by naming the stage that produces it, not only the path it was expected at.

The path on its own tells an operator that something is missing and not how to
get it, and an artifact stranded at an older path reads as a different fault
entirely.

## Losing some testimony is not the same as losing all of it

Losing every contributing document is a retraction; losing some of them is a replacement, and the second case needs a comparison the first does not.

`:retract` handles the empty case. `:replace` answers for any non-empty
composition, and it used to do so without comparing anything, so a partial
withdrawal wrote the new text and marked nothing. The comparison is made against
a stored census of which attachments contributed, which is why that census has
to survive a degraded run: `retain_with_notice` once replaced the whole census
with a single invented row, leaving the next comparison with an empty list and
no way to notice a withdrawal ever again. A fourth path reaches the same state —
candidates in hand, none producing text — and it keeps the carried census for
the same reason.

The census is keyed on the attachment id rather than on the label shown to
people. Legistar does not keep those labels unique, and when one of a pair
sharing a display name stopped contributing, the surviving twin's label masked
its absence and no draft was marked.

## Why an all-denied run explains itself

A run in which every candidate was denied used to be invisible end to end: every record removed, the mirror built from that same empty array, and a retraction reached with no attachments, no warning and no visible reason.

The admin mirror now carries the explanation, because "there is no testimony" and
"everything offered was rejected" look identical to a reader and mean opposite
things.

## Retracting evidence retires the conclusions drawn from it

Clearing testimony without marking the drafts written from it is half a fix, because nothing else on that path retires them.

Left unmarked, a draft whose evidence has been withdrawn stays approvable for
ever, and an operator approving it publishes a position resting on text Sway no
longer holds.

An operator's explicit clear needs the same treatment, and for a reason that is
easy to get backwards. The clear was assumed to make the bill-level gate refuse
by itself, and it does not when hearing testimony also exists — so the clear now
marks the drafts as well, and warns the operator before it does. Where both
guards could answer, the per-draft one answers first, because it names the
specific reason rather than the general one.

## The marks live on each draft, not on the bill

Whether a draft's evidence has been withdrawn is a key on that draft inside the existing JSON rather than a column on the row.

Drafts are approved one at a time, so the mark has to sit on one draft at a
time; a bill-level column could not say that one of four drafts is retired.
That also means a row can carry a retraction mark and fresh testimony at once,
which is the pairing a wholesale paste used to erase.

There is more than one such mark, and a paste has to carry every one of them
forward. Excluding only one from the key used to match a stored entry against a
pasted one left the other inside that key, so an entry carrying both could never
match again and its marks were lost on every paste.
