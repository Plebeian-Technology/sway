---
mode: explanation
summary: "Explains why bill fetching writes database rows before writing files to disk, so partial failures stay debuggable instead of silent."
status: agent-extracted
related: []
---
# Bill artifact write ordering

<!-- vale Vale.Spelling = NO -->

Why `FetchBillsService` writes database rows before it writes any file to
disk, and how that ordering decision is enforced two calls deep.

## Database rows first, files after

`FetchBillsService#call_discover` writes the `Bill` and `PipelineRunBill`
database rows FIRST, and only writes files (`metadata.json`, PDF bytes)
AFTER those rows commit.

The other order fails confusingly. If the database transaction rolled back
partway through, bill folders would sit on disk with no `PipelineRunBill`
rows to match them. The pipeline orchestrator's "zero bills succeeded" check
would then kill the whole run with a hard `StageError` — and `ls` on the
artifact folder would make the fetch look like it had worked anyway, because
the files are right there.

In the chosen order, a disk failure after the database commit instead leaves
rows whose `external_id` has no matching `metadata.json` (and no PDF). The later
`extract_text` stage records a `:skipped_no_pdf` result for that bill — marking
it `"skipped"` with error `"no_pdf_uploaded"` and resetting the consecutive-failure
counter — rather than aborting the run. The bill remains visible as skipped in the
Bill Creator per-bill grid, allowing an operator to inspect it and attach a PDF or
backfill if needed.

### What this looks like to an operator

The database commit finishes fast: one transaction, for about 166 bills.
Then the file-writing loop spends several more minutes pulling attachments
from Legistar. During that window, an admin watching the Bill Creator sees
the bill picker fill up before the per-bill grid shows any progress. The
activity log stays quiet during this gap, because its broadcasts fire only
when a `PipelineRunBill`'s status changes — which is not true on the row's
first insert. That visible gap is expected behavior, not a consistency bug.

## `persist` protects that guarantee at the write itself

`FetchBillsService#persist` writes `metadata.json` to disk BEFORE it
attempts the network fetch for the PDF. That ordering is what
keeps a failed PDF download scoped to one bill: the bill can be backfilled
later (through `mode: :backfill_missing`, which `#repair_missing_metadata`
also reaches), instead of the failure stopping the loop for every bill after
it.

`#persist` rescues filesystem errors (`SystemCallError`, `IOError`) here
too, not just network errors (`Faraday::Error`). Three writes can happen
from this method: `FileUtils.mkdir_p`, the `metadata.json` write, and
`#download_pdf`'s `File.binwrite`. Before this rescue existed, a full disk,
a read-only mount, or running out of file handles passed straight through
`#call_discover` — which rescues only `Faraday::Error` and
`Legistar::Client::Error` — as a run-killing `StageError`.

That contradicted the write-ordering decision above: database rows are
written BEFORE the file-writing loop precisely so that a disk failure
leaves bills that can be backfilled, rather than failing the whole run. The
filesystem-error rescue in `#persist` is what makes that guarantee actually
true in practice, not just true in the happy path.
