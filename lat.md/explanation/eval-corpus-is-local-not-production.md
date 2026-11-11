---
lat:
  mode: explanation
---
# Why the eval corpus is the local database, not a production snapshot

The eval harness measures against whatever corpus the local machine holds, not a copy of production's database.

This section records what forced that, what it replaced, and what it means the harness can and cannot answer.

## What the corpus is

The eval corpus is the local development database plus its regenerated diff-markdown artefacts, from a full local pipeline re-run over every bill.

It is not a snapshot copy of production's database, and it is not a subset chosen to match one.

## Why it is not the production snapshot

`BillSummaryPromptBuilder`'s source section is read from a filesystem artefact the `.sqlite3` snapshot does not contain, and that artefact cannot be reproduced from the snapshot or fetched from production.

`<LEGISLATION_ROOT>/diffs/<locale>/<external_id>.md` holds the diff text; diffs live on disk, not in the database. A local checkout holds only some of them, covering only some of the snapshot's rows. They cannot be regenerated from the snapshot — `bill_amendment_operations` has no rows there, so there is no operation log to replay — and they cannot be fetched from production on demand. Production's exact prompt bytes are reachable only through a copy someone supplies, so the harness does not depend on one.

## What this supersedes

Three earlier decisions rested on the snapshot as the measurement population. Each now rests on the local corpus instead; the *method* each one established survives, only what it measures against changes.

- **The reference population.** The set was to be drawn from the snapshot's rows. It is now drawn from the local corpus after a full pipeline re-run, which produces complete diff-markdown coverage rather than partial coverage.
- **The retrospective parity check.** The full check was to re-run the builders against a copy of the snapshot and compare hashes to the manifest. There is no production reference left, so that re-run step is dropped. What survives is the manifest, the hash comparison, and the builder-git-sha staleness spec — together the whole of what "parity" now means.
- **The band tallies (the measurement basis of the size bands).** Size-band counts measured against the snapshot are snapshot-specific and are not carried into any plan as ids or counts; the bands are re-measured against the local corpus, and the re-measurement task commits its own output so the choice can be reproduced.

## What parity means now

Parity was always checked on hashes, not on byte-for-byte diffing at review time; what changes is what the hashes are checked against.

The committed manifest records a SHA-256 of the system prompt and the user message the harness actually dumped, plus a content-digest over the builder files that produced them. A later spec fails if the builders (or the constants they read) change without the manifest's recorded digest moving. That is the whole of the parity story now: proof that the committed prompt bytes are the bytes today's builders emit, not proof that they match anything production ever sent.

## The two questions, restated

This harness answers which model writes the best summaries and positions for Sway's prompts, against the data the local corpus holds.

It does not answer whether production's past output was any good — that question needs production's own prompt bytes, which are out of scope. It also cannot rank the model doing the judging, for a reason already decided: the harness's judge is never scored by anything else in the same run.

## The accepted cost

The eval runs only where the local corpus exists. It cannot run on a fresh clone, and it cannot run in CI.

`lib/tasks/classification_corpus_measure.rake` already carries this same limitation, accepted here for the same reason: reproducing the corpus on demand is a bigger project than the harness itself, and the harness is more useful running narrowly than not running at all. Nothing in the harness reads or requires an untracked production snapshot, and no task aborts because that file is absent. It remains a useful cross-check for anyone who happens to have it, and nothing treats it as a requirement.
