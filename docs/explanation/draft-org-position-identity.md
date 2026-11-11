---
mode: explanation
summary: "Explains how a content-hash token identifies one draft org position entry, since the array itself gives entries no stable id."
status: agent-extracted
related: []
---

<!-- vale Vale.Spelling = NO -->

# Identifying one entry in draft_org_positions

`draft_org_positions` is a plain JSON array stored on `BillLlmProvisioning`.
Nothing about that array gives one entry a stable identifier, so this
document covers how `BillLlmProvisioning` works one out, and how it decides
whether a caller actually named a particular entry.

## draft_token: an identity worked out from content

`BillLlmProvisioning.draft_token(entry)` is an identity token for ONE entry
of `draft_org_positions`, worked out from that entry's own content. It keeps
the first `DRAFT_TOKEN_HEX_CHARS` (16) hex characters of a SHA-256 hash of
the entry — 64 bits. The token only has to tell apart at most a few dozen drafts
on one bill, and it is not a secret, so the short form is ample and keeps the
URLs and request parameters that carry it readable.

### Why it exists

The code that changes a draft by its position in the array —
`ApproveOrgPositionService#delete_approved_draft`'s `delete_at`, and
`BillDraftOrgPositionsController#update`'s `delete_at` / `drafts[index] =` —
used to check the draft's `org_name` first. A name is not an identifier.
Nothing stops two entries in the array from sharing one:

- `config/schemas/bill_positions.json` describes `draft_org_positions` as a
  plain array with no rule that entries must differ, and `org_name` as a
  plain string with no rule at all.
- `BillPositionsPromptBuilder` asks the model for "Name of the organization
  OR INDIVIDUAL", so a coalition and one of its affiliated speakers can quite
  legitimately arrive under a single label.
- `PasteSummaryService` accepts any array an operator pastes in, so long as
  it is well-formed.
- The controller's edit path will rename one draft to match another if
  asked.

With two same-named drafts the name could not tell them apart, so an
out-of-date index slipped through the check and destroyed the wrong entry
while the audit line named the right organization.

### Why hashing the content is enough

Two entries with the SAME token are byte-for-byte identical, so acting on
either leaves the same array behind (the same collection, minus one identical
copy) and writes the same audit line — there is no "wrong one" anybody could
notice. Any two entries you could tell apart get different tokens.

A planned `BillDraftOrgPosition` model will give each draft a real database
id; until then this token is worked out on demand and never stored, so it
needs no migration and no backfill.

Keys are sorted before hashing so the token does not change with JSON key
order.

## The frontend's `IOrgPosition.draft_token`

An identity for this entry that the server derives from its content: a
shortened SHA-256 hash of the entry's canonical JSON. It is computed as the
payload is built and never stored, so it is missing from anything the
browser builds itself and from any payload assembled another way — hence
optional. Approve and Reject send it back, so an out-of-date position
number cannot act on a neighbouring entry that happens to name the same
organization. The name alone could not prevent that: nothing stops two
entries in `draft_org_positions` naming the same organization.

## Why `TDraftOrgPosition` carries `rawIndex`

A draft position together with its position in the UNFILTERED
`bill_llm_provisioning.draft_org_positions` array. The UI hides old
entries marked `rejected: true` before rendering, but both pieces of
server code that act on an entry
(`ApproveOrgPositionService#delete_approved_draft` and
`BillDraftOrgPositionsController#update`) count into the unfiltered array.
So the original number has to survive the filtering rather than being
recounted from what ended up on screen.

## draft_identity_asserted?: did the caller say which draft it means?

`BillLlmProvisioning.draft_identity_asserted?(name:, token:)` is the single
answer to "did the caller say which draft it means?", and (via
`draft_identity_mismatch?` below) the single answer to "the caller named a
draft, and this entry is not it".

Both questions used to be answered in two places —
`BillDraftOrgPositionsController#draft_identity_mismatch?` and
`ApproveOrgPositionService#asserted_identity?` / `#entry_mismatch?` — each
describing itself as a copy of the other, and they had already drifted
apart: the controller read an empty name as naming nothing, while the
service read it as naming the empty name. Same card, same parameters,
opposite answers, and on the approve side a refusal that no page reload
could clear. Two spellings of one question is the drift; one spelling is the
fix.

An empty string names nothing. By the time a value reaches this method, an
unfilled form field and a missing parameter look identical, and neither
picks a draft.

## draft_identity_mismatch?: does this entry match what the caller named?

When a token is given, the token decides: a name cannot pick out a draft,
because nothing stops two entries in the array from sharing an `org_name`.
When no identity was asserted at all, the answer is `false` — whether that
is allowed is each caller's decision, this method only reports it.

## Querying for a non-empty draft_org_positions

`draft_org_positions` is `serialize ..., coder: JSON`. A hash condition
dumps its comparison value through that coder on the way into SQL, and an
Array value is additionally read as an IN-list rather than as one scalar, so
every typed spelling for "not empty" on this column misses:

```ruby
where.not(draft_org_positions: "[]")  # => ... != '"[]"'   (coder dumps it)
where.not(draft_org_positions: [])    # => 1=1  (not-in-empty-set)
where.not(draft_org_positions: [nil, []])
                                       # => NOT (1=0 OR ... IS NULL)
where("... != ?", "[]")               # correct, but Rails/WhereNot
                                       #   autocorrects it back to the
                                       #   first form, silently
```

while the bytes actually stored for an empty array are `[]`. Arel's
`#not_eq` is the one spelling that both compares as a scalar (no IN-list
flattening) and passes the deserialized value through the column's coder,
yielding `!= '[]'`:

```ruby
BillLlmProvisioning.arel_table[:draft_org_positions].not_eq([])
```

It is also the one spelling rubocop cannot rewrite — a bound-raw-fragment
version of this fix was autocorrected straight back into the bug by the
pre-commit hook.

The old `""`-sentinel some rows carried is dropped rather than translated:
the JSON coder never dumps a bare empty string, so no writer going through
the coder can produce that value; a direct `raw.blank?` check on the Ruby
side still catches one if a direct-SQL write leaves it behind.

## draft_org_positions_for_client: the version the browser sees

`BillLlmProvisioning#draft_org_positions_for_client` is the value sent to
the browser: every Hash element of `draft_org_positions` gains its
calculated `draft_token`, so the client can hand the token straight back on
Approve, Reject, or Edit. The token is worked out here, at serialize time,
and never saved — the stored array never holds a `draft_token`, and the
controller's list of editable fields does not accept one, so a request
cannot smuggle a fake token into storage through the edit path.

A value that is not an Array (the column may be empty) and elements that
are not Hashes pass through untouched, so an old `{"rejected" => true}`
stub still renders and still has no identity — which is correct, because it
is not a draft anyone can act on.

## Why the idempotency spec runs every example twice

`spec/requests/bill_draft_org_positions_idempotency_spec.rb` runs every
example over both ways a caller can say which draft it means. The card
sends BOTH `draft_org_name` and `draft_token`
(`BillCreatorOrgPositionCard`), and `draft_identity_mismatch?` takes a
completely different branch when a token is present — a digest comparison,
not a string compare on the name. The name-only arm, which used to be all
this file exercised, is the path production does not actually take. The
token is read off the row rather than typed out in the spec, because it is
a digest of the whole entry: writing one down would pin the digest instead
of pinning the branch.

## No portable SQL for Ruby's blank?

Testing this column's sibling testimony columns (`extracted_testimony`,
`supplemental_testimony`) for whitespace-only content has to happen in
Ruby, not SQL: no portable SQL expression reproduces Ruby's `blank?`.
SQLite's `TRIM` strips spaces only, while `blank?` also strips
`\t \n \v \f \r` and Unicode separators. A `TRIM` spelling would close the
common case and leave a narrower version of the same disagreement — worse
than either alternative, because it would look closed.
