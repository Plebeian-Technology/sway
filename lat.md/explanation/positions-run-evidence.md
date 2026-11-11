---
lat:
  mode: explanation
---

# Evidence for an organization-positions run

`GenerateBillSummaryJob` buys a paid AI call to extract organization positions only when a bill has testimony.

`GenerateBillSummaryJob` buys a paid AI call to extract organization positions only when a bill has testimony, and needs to check both whether that call is still owed and whether the evidence it would read has moved since a purchase decision was made. `BillLlmProvisioning` answers both questions.

## testimony_digest: a fingerprint of the evidence

`BillLlmProvisioning#testimony_digest` is a fingerprint of the evidence a positions run reads, so a writer that moves that evidence while the paid call is in flight can be seen at the persist.

`GenerateBillSummaryJob` takes this digest inside the lock that decides to buy the positions call, and its persist step declines the wholesale `draft_org_positions` write when the committed value no longer matches.

### Why not testimony_present?

`#testimony_present?` is the wrong question here: it asks whether the bill has ANY testimony, and evidence goes away one attachment at a time as well as all at once.

`#testimony_present?` is the wrong question here: it asks whether the bill has ANY testimony, and evidence goes away one attachment at a time as well as all at once — `FetchHearingsService`'s `:replace` arm writes a shorter composition, and both `SupplementalTestimonyWrite` mark writers move a column that arm never touches. All four leave the bill-level answer `true` while the drafts on the row rest on evidence that is gone.

### What goes into the digest

BOTH columns, in the order `BillPositionsPromptBuilder` joins them, so text moving from one to the other still changes the answer.

The NUL separator is what keeps the join unambiguous: without it `"AB" + ""` and `"A" + "B"` digest the same.

### Reading a mismatch

A change in either direction — evidence added as well as removed — reads as a mismatch, and that is the intended reading.

The answer was drawn from a snapshot that no longer exists, and the write it feeds replaces a whole column carrying another writer's retraction marks.

## positions_owed?: is the call still owed?

`BillLlmProvisioning#positions_owed?` is true when the positions call is still owed on this row.

That call fires only for a bill with testimony, and a successful one always writes `draft_org_positions` — an empty list when the model named no organization, which is an answer and not an absence. Testimony with a `nil` column therefore means the call was never made, or was made and never landed.

`GenerateBillSummaryJob` reads `#positions_owed?` when a retry arrives carrying its own purchase marker. The marker says the enqueue spent money; it cannot say on which of the two calls, because both stamp the same value. This is the question the marker cannot answer, and the row can.

## testimony_present?: one answer to two questions

`BillLlmProvisioning#testimony_present?` answers two different questions at once.

`BillLlmProvisioning#testimony_present?` answers two different questions at once: whether `GenerateBillSummaryJob` should ask the AI for organization positions, and whether the Bill Creator should show its "No public testimony available" empty state. Both questions reduce to the same test — does the bill have any testimony at all — so one method answers both rather than two copies of the same `extracted_testimony.present? || supplemental_testimony.present?` check drifting apart.
