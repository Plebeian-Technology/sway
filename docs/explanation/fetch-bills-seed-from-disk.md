---
mode: explanation
summary: "Explains why FetchBillsService#seed_from_disk rebuilds database rows from metadata.json without calling Legistar, and why its jurisdiction sweep is scoped by name."
status: agent-extracted
related: [pipeline-run-bills-seeding, bill-external-id-validation]
---
<!-- vale Vale.Spelling = NO -->

# Why `FetchBillsService#seed_from_disk` exists

`#seed_from_disk` rebuilds the `Bill` and `PipelineRunBill` rows from the
`metadata.json` files already on disk, with no call to Legistar at all. The
discover path writes one `legislation/bills/raw/<external_id>/metadata.json`
per bill (see `#persist`); this reads those files back and feeds them
through the SAME `#seed_ar_rows` discover uses.

The SQLite database lives in the `sway_storage` Docker volume, but
`legislation/bills/` is a folder shared in from the host machine.
Destroying the volume (`dip provision`, `db:reset`) wipes every `Bill` and
`PipelineRunBill` row while every downloaded file survives. When discover
mode was the only way to create those rows, a full run in that state failed
with the misleading "all bills failed in stage extract_text" — even though
text and PDF files for the whole bill set were sitting right there on disk.
See [Why RunLegislationPipelineJob pre-seeds pipeline_run_bills](pipeline-run-bills-seeding.md)
for the caller-side half of this fix.

`#seed_from_disk` does not care where the metadata came from: `#seed_ar_rows`
treats rows read from disk exactly like rows read from Legistar. It respects
single-bill runs through `#scope_to_run_bill`, and `#seed_ar_rows`'
`find_or_create_by!` makes it safe to run twice, so a later discover-mode
fetch in the same run just finds the rows already there. It returns the
count of metadata files loaded (0 when there are none), and skips the
locale lookup entirely in that case — so a brand-new install with nothing on
disk does not raise.

## Why `#read_disk_metadatas` copies each field across by hand

`#read_disk_metadatas` reads every
`legislation/bills/raw/<sway_locale>/<external_id>/metadata.json` back into
the symbol-keyed `metadata` shape `#seed_ar_rows` expects — the reverse of
`#persist`. Each field is copied across one at a time, rather than renaming
every key in bulk, so a hand-edited or half-written `metadata.json` cannot
sneak unexpected keys or types into the seeding path: a row with a blank
`external_id` or a `matter_id` that is not an `Integer` is skipped, and
corrupt JSON is skipped instead of killing the whole rebuild. Rows are
sorted by `external_id` so `#seed_ar_rows` hands out the same `sort_order`
every run.

The malformed-JSON rescue and the file-read rescue are kept as separate
`rescue` clauses so the logged warning says which half broke: `JSON::ParserError`
covers a file that parses to garbage, while `SystemCallError`/`IOError`
covers a file that cannot be READ at all (permission denied, an I/O error,
too many open files, or one deleted after the glob listed it). Without the
second rescue, one unreadable file would kill the rebuild for EVERY bill
before any stage ran.

## Why the disk sweep is scoped to this service's own jurisdiction

The glob only reads `artifact_root.join(sway_locale_name, "*",
"metadata.json")` — both the locale segment and the external_id segment
matter. The files moved down one level when they gained their
`sway_locale` segment; the old two-part glob pattern (missing the locale
level) matched nothing, so a resume from that state silently seeded zero
bills — a failure mode that looks exactly like "there is nothing on disk
yet."

Deepening the glob pattern alone would have been worse than the bug it
fixes: `#seed_from_disk` stamps EVERY row it gets with
`#resolve_baltimore_locale`, so a sweep across all jurisdictions would take
another city's bills and record them as Baltimore's. Naming the locale
segment keeps this service reading only what it wrote.
