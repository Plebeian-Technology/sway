---
mode: explanation
summary: "Explains how ApproveOrgPositionService turns the :index parameter into one draft_org_positions entry, and two bugs that shaped the current handling."
status: agent-extracted
related: []
---

<!-- vale Vale.Spelling = NO -->

# Resolving :index to a draft

`ApproveOrgPositionService` addresses one entry of `draft_org_positions` by
array position, carried in the `:index` parameter. Three methods work
together to turn that value into an entry or a firm "no entry," and every
guard that needs the draft goes through them so they can't disagree about
what "the draft at `:index`" means.

## draft_at: the one place :index becomes an entry

`#draft_at(drafts)` returns `nil` when the index resolves to no entry —
unparseable, negative, or past the end of the array.

The negative case is not merely defensive. Ruby's `Array#[]` wraps around,
so `drafts[-1]` is the LAST draft. Resolving a negative index the normal way
would silently address a different draft than the operator saw.

`nil` does double duty here: the array may legitimately hold a `nil`
element, so "no entry" and "a `nil` entry" look the same in the return
value. That's safe because both callers treat both readings the same way —
`draft_identity_mismatch?(nil, name:)` compares `""` against an asserted
name and reports a mismatch, and `draft_evidence_retracted?(nil)` is false.

## draft_index: parsing an Integer or a String

The draft card is a React component, so it sends `index` as a JSON number,
which arrives here already an Integer. A form or a hand-written request
sends the same thing as text. Both have to be handled separately.

Forgetting that once broke every Approve click in the Bill Creator.
`Integer(value, 10)` REFUSES a value that is not text — "base specified for
non string value" — so calling it with `exception: false` on an Integer
input quietly gave back nothing for the one caller that matters (the
card). Nothing resolved, the request answered that the draft list had
changed, and no amount of looking at it again could help. Only a browser
could catch it: every other test sent the number as text, where the same
line worked.

Text is read as base 10 on purpose. Left to guess, Ruby reads `"010"` as 8
and `"0x10"` as 16, so a spelling the operator never saw could land on a
real draft. This split — number and text answered apart, never one call for
both — is what the other id readers in this codebase do too
(`Legistar::Client`, `FetchHearingsService` twice, `Legislation::BillMetadata`).

## draft_index_mismatch?: an unresolved index is a mismatch, not a no-op

When `#draft_at` returns `nil` and the caller asserted an identity, that's a
MISMATCH, not a silent no-op.

It used to be treated as a no-op, on the reasoning that an out-of-range
index could destroy nothing in `#delete_approved_draft`. But that covered
destruction only: by the time the delete no-opped, `#call` had already
upserted the Organization and a PUBLIC `active: true`
`OrganizationBillPosition` — the approval PUBLISHED, asserting a named
organization's stance on the bill from a draft the operator had rejected,
or from no draft at all. The guard failed open in the very circumstance
that makes an index stale: the array shrank.

The caller asserted "the draft at `:index` is THIS one." No draft exists
at `:index`, so the assertion is false. `:draft_index_mismatch` is also the
right outcome to report: it sends the operator back to a list the redirect
has just refreshed, which is the remedy for a list that moved under them.
