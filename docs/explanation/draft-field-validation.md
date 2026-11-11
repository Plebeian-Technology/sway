---
mode: explanation
summary: "Explains how draft org position stance and text-length limits are read from the JSON schema instead of being duplicated."
status: agent-extracted
related: []
---

<!-- vale Vale.Spelling = NO -->

# Validating fields on a draft org position

`BillLlmProvisioning` reads two limits for a `draft_org_positions` entry
straight off the JSON schema, rather than typing them out again: the allowed
`stance` values, and the maximum length of `org_name` and `summary`.

## DRAFT_STANCES: the three words a draft's stance may hold

`DRAFT_STANCES` is taken from the schema file rather than duplicated here.

Everything that WRITES this array is schema-checked, but the two writers
read DIFFERENT files. The language-model job checks against
`config/schemas/bill_positions.json`, the file `DRAFT_STANCES` is built
from. The paste path checks against the duplicate `draft_org_positions`
fragment inside `config/schemas/bill_summary.json`. The two copies cannot
drift apart unnoticed: `spec/config/bill_summary_schema_spec.rb` runs the
same cases against both.

One writer is checked by neither: `BillDraftOrgPositionsController`'s edit
branch merges whatever `stance` the request carried straight into the
stored entry. An unknown word there is not a stored typo — it is a card
that renders with a blank badge and an editor whose menu matches nothing,
and the operator only finds out when Approve refuses with `:invalid_stance`
and no way to see why.

`fetch` is used all the way down the schema path on purpose: if the schema
is restructured, this raises at boot rather than quietly becoming an empty
list that rejects every stance.

## DRAFT_TEXT_MAX_CHARS: the longest an org name and a summary may be

`DRAFT_TEXT_MAX_CHARS` is read off the same schema that bounds a generated
one.

### Why these have to be asked somewhere other than the schema

Every other writer of `draft_org_positions` hands its whole payload to the
schema, so the schema's length limits apply automatically. The admin edit
endpoint merges the fields a request names into one stored entry and never
builds a payload, so it went past them — the same gap the stance check
above was added to close, one field over. What lands is not a long typo: it
goes into a serialized JSON column that every later read of this bill loads
whole.

### No minimum is enforced here, on purpose

The schema asks for at least one character, but clearing a summary is an
ordinary step while rewriting one, and a blank value cannot reach the
public record: `ApproveOrgPositionService` refuses a blank org name and a
blank summary before it writes anything.

`fetch` is used all the way down for the same reason `DRAFT_STANCES` gives
above: a restructured schema raises at boot instead of quietly becoming
`nil` and bounding nothing.

## Why draft_text_too_long? treats a field with no cap as never too long

`draft_text_too_long?` looks `field` up in `DRAFT_TEXT_MAX_CHARS` and
returns `false` when the field has no entry there. `stance` is the one
`draft_org_positions` field with no length cap, because it is checked
against `DRAFT_STANCES` — a fixed allow-list of words — rather than typed
as free text with a maximum length. A field the schema does not bound by
length is not a gap in this check; it is a field this check does not own.
