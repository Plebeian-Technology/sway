---
lat:
  mode: explanation
---

# Why DeleteWrongYearCongressRollCallVotes condemns a whole bill, not single rows

The wrong-year fetches did two kinds of damage to a bill's roll-call rows: they CREATED rows in a later year than the vote, and they OVERWROTE the support on rows that had been right.

The wrong-year fetches did two kinds of damage to a bill's roll-call rows: they CREATED rows in a later year than the vote, and they OVERWROTE the support on rows that had been right — and an overwritten row keeps its original `created_at`. A row the other vote happened to agree with is untouched and still right, so single rows cannot be sorted into good and bad by timestamp alone.

Bills can be sorted, though: a bill holding even one row created or updated in a later year than its own vote was fetched against the wrong year. On every such bill, the migration deletes ALL rows with `source: "congress"` that are not inferred — one wrong-year row condemns every `source='congress'` non-inferred row on that bill — and the fixed fetcher restores the real roll call from upstream on the next sweep.

`spec/data/delete_wrong_year_congress_roll_call_votes_spec.rb` exercises this per-bill condemnation rule directly. See [[docs/explanation/production-migration-spec-design.md|Why the vote/link/sponsor helper queries carve out wrong-year cleanup rows]] for how the production migration-chain spec treats the same rows before this cleanup has run against a given snapshot.
