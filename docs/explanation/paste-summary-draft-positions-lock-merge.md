---
mode: explanation
summary: "Explains why PasteSummaryService computes the draft_org_positions merge inside the same lock that writes the row, instead of reading the stored list earlier."
status: agent-extracted
related: ["docs/explanation/paste-summary-draft-positions-testimony-guard.md"]
---
# Why the draft-positions merge happens inside the write lock

<!-- vale Vale.Spelling = NO -->

`PasteSummaryService#write_pasted_body!` locks the provisioning row
first, and only then works out what the new `draft_org_positions` column
should hold, inside that same lock:

```ruby
def write_pasted_body!(provisioning, attrs, body)
  if provisioning.new_record?
    ApplicationRecord.transaction { commit_pasted_body!(provisioning, attrs, body) }
  else
    provisioning.with_lock { commit_pasted_body!(provisioning, attrs, body) }
  end
end
```

## What the merge is doing

`#draft_positions_attrs` carries internal marks forward from the
currently stored `draft_org_positions` list onto the pasted one — which
draft an operator has rewritten, which one had its evidence withdrawn
(see
[internal-draft-marks.md](internal-draft-marks.md)). It does this by
matching entries between the two lists by content, not by array
position (see
[draft-org-position-identity.md](draft-org-position-identity.md)).

## Why reading the list earlier was wrong

An earlier version of this code read the stored list once, at the top of
`#call`, and wrote the merged result further down. Anything that changed
the `draft_org_positions` column in between was invisible to that merge:
an operator rejecting a draft in another browser tab, the summarize stage
persisting its own positions, or a mark stamped moments earlier by
another writer. The paste would then compute its merge against a copy
that no longer matched the database, and write a result missing a mark
that really had been there — with nothing left to show it had ever
existed.

`GenerateBillSummaryJob` solved the same problem for its own writes with
`#persist_unless_superseded!`, which decides what to write from committed
state read under a lock. `write_pasted_body!` is the same arrangement for
the other writer of this column: read the current value under the lock
that is about to replace it, not the value that was current when the
request first arrived.

`with_lock` reloads the row as part of taking the lock, so
`provisioning.draft_org_positions` inside `#commit_pasted_body!` is
whatever is about to be overwritten, not a stale copy.

## The one exception: a row that does not exist yet

A brand-new provisioning row can't be locked — there is nothing in the
database yet to lock. But there is also nothing else that could be
concurrently writing to a row nobody has created, so that case only needs
a plain `ApplicationRecord.transaction`. That's the only difference
between the two branches in `#write_pasted_body!`.
