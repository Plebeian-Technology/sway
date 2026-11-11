---
mode: explanation
summary: "Why FetchedBillsPanelSerializer and ResourceCachePanelSerializer read pipeline state instead of a dedicated cache table, and how each stays safe against filesystem and stage-result surprises"
status: agent-extracted
related: [docs/explanation/pipeline-artifact-presence-overview.md]
---

# Bill Creator's two artifact panel serializers

`BillCreator::FetchedBillsPanelSerializer` and
`BillCreator::ResourceCachePanelSerializer` are twins on the Pipeline & LLM
tab: `ResourceCachePanelSerializer` shows the cache state of each tier for a
single bill, assembled from the Ruby pipeline's own state
(`PipelineRunBill.stage_results` and `BillLlmProvisioning.llm_generated_at`)
rather than a dedicated cache table. `FetchedBillsPanelSerializer` shows
what is actually sitting on disk across ALL bills in a locale, whether or
not any pipeline run recorded it. Before this panel existed,
seeing what had been fetched meant logging into the server or opening a
Rails console.

## `FetchedBillsPanelSerializer`

### Why it walks the disk instead of the database

It lists every bill that has files on disk under
`legislation/bills/raw/<sway_locale>/<external_id>/`, the folder tree
`FetchBillsService` writes into. Reading one segment too shallow listed the
`sway_locale` folders themselves and no bills at all, silently.

A folder on disk with no matching `Bill` row in the `sway_locale` being
asked about still gets a row, with `bill_id` left nil. Showing those
stranded downloads is the whole point of this panel.

### Why it is scoped to one locale

Only that `sway_locale`'s own subtree is read, never the whole raw root.
Every row is stamped with the `sway_locale` asked for, so sweeping all of
them would report one city's stranded downloads as another city's — the
trap `FetchBillsService#read_disk_metadatas` names.

### Why an unusable locale name degrades instead of raising

An unusable `sway_locale` name comes back as "nothing on disk" rather than
raising, because this feeds an admin panel and one bad row must not take
the page down.

### Why the spec fixtures build paths through `Legislation::Paths`

`spec/serializers/bill_creator/fetched_bills_panel_serializer_spec.rb`
builds every fixture path through `Legislation::Paths`, the same builder
`FetchBillsService` writes through, rather than spelling the layout out by
hand. Spelling it out separately once let the fixture drift to the
reader's wrong depth — the exact defect above — so both agreed
with each other and neither could fail.

The spec's `seed_bill_dir` helper builds a bill's file directory under a
throwaway temp root through that same builder, so the fixture cannot
disagree with production about where a bill lives. Its `attachment_names`
argument seeds a folder `FetchBillsService` does NOT create — real
testimony attachments live under their own root, keyed by `sway_locale`
and by Legistar attachment id rather than by bill.

## `ResourceCachePanelSerializer`

### Why `pdf` and `summary` are handled outside `TIER_TO_STAGE`

`pdf` is missing from `TIER_TO_STAGE` on purpose. Fetching bills happens
once per pipeline run, not once per bill, so it writes nothing into
`PipelineRunBill.stage_results`. `build_row` handles the pdf row on its own
by reading the modification time of the PDF that `FetchBillsService` drops
at `legislation/bills/raw/<sway_locale>/<external_id>/*.pdf`, found with the
same pattern `RunLegislationPipelineJob#locate_pdf` uses.

`spec/serializers/bill_creator/resource_cache_panel_serializer_spec.rb`
checks that the props keep their shape: the React `ResourceCachePanel`
still gets the same array of hashes it used to get from
`BillArtifactMirror#to_builder_hash` — only the source of the data has
changed, to `PipelineRunBill.stage_results`, `BillLlmProvisioning`, and
(for the pdf row) the modification time of the PDF on disk. The pdf row's
timestamp fixture points the legislation raw root at a temp folder through
the `legislation` setting, the way `GenerateDiffsService::ResultWriter`
does, so tests never write into a developer's workspace.

Its `stage_results` fixtures use `"at"` as the timestamp key deliberately —
see [Why the key set is checked against the real method, not a hand-typed
fixture ](pipeline-stage-results-json-set.md#why-the-key-set-is-checked-against-the-real-method-not-a-hand-typed-fixture)
— because `#record_stage_result`, the key set this serializer reads, pins
that key; this fixture must not drift to a key production never produces.

`summary` is handled on its own too. It comes from
`BillLlmProvisioning.llm_generated_at`, because the summarize step runs
inline through `GenerateBillSummaryJob` and writes the provisioning row
rather than `stage_results`.

### Why a missing tier is left out of the array rather than sent as "not cached"

Leaving a tier out is safe: the React panel walks its own `TIER_ORDER` list
and shows "Not cached" for any tier missing from the array, so sending only
the tiers that produced something looks exactly the same on screen.

### Why an old external id degrades to "no PDF" instead of raising

`Legislation::Paths` builds the search pattern, cleaning up the
`external_id` first. This feeds an admin panel, so an old id it cannot make
sense of has to come back as "no PDF" instead of taking the page down —
which is why the cleanup step returns nil rather than raising, the same
choice `Pipeline::ArtifactPresence` makes (see
[Pipeline::ArtifactPresence overview](pipeline-artifact-presence-overview.md)).

## The frontend types (`app/frontend/types/bill_creator.ts`)

### Why ILegislationPipelineRun and IBillLlmProvisioning are not redeclared there

`bill_creator.ts` must NOT declare `ILegislationPipelineRun` or
`IBillLlmProvisioning` again — those are extended where they already live.

### What `bill_creator.ts` types

TypeScript types for the props the Pipeline & LLM tab receives. They match
the shapes Rails sends: the `pipeline_run_bills` array from
`LegislationPipelineRun#to_builder`, and the top-level
`bill_artifact_mirrors` prop.

### Why ResourceCacheTier's TypeScript names are neutral rather than matching the old Rails model name

The Rails table this used to come from is gone; the React
`bill_artifact_mirrors` prop is now built by
`BillCreator::ResourceCachePanelSerializer`. The prop's KEY is held fixed
so the shape the UI depends on stays stable, but the TypeScript type names
were changed to neutral ones, so nobody searches for "BillArtifactMirror"
expecting to find a Rails model.

### Why ResourceCacheRow has no path field

The server no longer sends `path`, the file's location on disk; the UI
never showed it. If it comes back, give it a panel of its own.

### FetchedBillsRow vs ResourceCacheRow on the frontend

`FetchedBillsRow` is a list of every bill that has files on disk under
`legislation/bills/raw/<external_id>/`. It feeds `FetchedBillsPanel` in the
Pipeline & LLM tab. `ResourceCacheRow` has one entry per bill per kind of
artifact; `FetchedBillsRow` has one entry per folder on disk, linked back
to the bill row when there is one. It matches
`BillCreator::FetchedBillsPanelSerializer#build_row` exactly. A folder with
no matching Bill row in the locale being queried comes back with
`bill_id=null`, `title=null` and `bill_row_exists=false`.
