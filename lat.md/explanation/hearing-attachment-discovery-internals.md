---
lat:
  mode: explanation
---

# Hearing attachment discovery: state, bookkeeping, and identity

`FetchHearingsService` is built fresh per bill (a new instance every call, including inside `#call_backfill_missing`'s loop), so its instance variables never accumulate across matters.

This document covers why they are still worth having as instance state, how the service tracks what it could NOT read, and how it decides one attachment's identity across two Legistar collections.

## Why the caches start as empty collections, not nil

`@event_ids`, `@matter_exists`.

`@event_ids`, `@matter_exists`, `@unswept_event_ids`, `@unswept_collections`, `@content_pending_ids`, `@content_unreadable_ids`, and `@content_denied_records` are all initialized to an empty `Hash` or `Array` (never left `nil`), and the four `@discovery_*` counters start at `0`. Every reader used to write `.to_i` or an `||` fallback to cope with a possibly-unset value, and that collapsed "this has not run yet" and "this ran and found nothing" into the same value by accident rather than by decision. Starting them empty/zero makes the collapse the decision: a reader is only ever asked to interpret an empty cache after the phase that would have filled it has already run, so the ambiguity in a zero count is whatever `#nothing_qualified?` already argues about, not a new one.

`@event_ids` and `@matter_exists` exist because TWO callers ask the same question about the same matter: `#call_discover` (building the hearing metadata array) and `#fetch_event_item_matter_attachments` (attachment discovery) both need a matter's event ids, and `#matter_exists?` is asked by `#verify_matter_exists!`. Caching means each bill makes the underlying request once, and the cache is written on the failure paths too (see `#memoize_no_events`), so a failure that was already rescued is not quietly retried by the second caller.

## Unswept bookkeeping: recording what this run could NOT read

`@unswept_event_ids` and `@unswept_collections` record.

`@unswept_event_ids` and `@unswept_collections` record, respectively, one event whose attachments this run could not read, and one whole COLLECTION (`Matters/<id>/Attachments`, `Matters/<id>/Histories`, `Events/<id>/EventItems`) that came back unreadable. Both degrade to `[]` by design when their upstream call fails, which makes the failure invisible in the discovery counts unless it is written down separately.

`#mark_event_unswept` and `#mark_collection_unswept` are each the ONLY place their respective fact gets recorded, so the several call sites that can reach the same conclusion cannot disagree about whether they wrote it down. Both are safe to call twice for the same id/route: two ways of reaching "this was not read" cannot both happen for the same event today, but `#call_backfill_missing` re-enters `#call_discover` per bill on a fresh instance, and a repeat must not be counted twice.

An unread `Matters/<id>/Attachments` collection is the MORE damaging of the two collection failures to miss: the matter's own attachments still make `@discovery_found` positive even when the OTHER collection went unread, so `#nothing_qualified?` could fire on a tally that is missing a whole endpoint. That is why `#fetch_matter_attachments` type-checks every ROW, not just the outer array — `#dedupe_key` reads `entry[:raw]["MatterAttachmentId"]` with no type check of its own, and it runs before the `.pdf` gate can drop anything, so a `null` or a bare number in the list used to raise `NoMethodError` out of `#discover_attachments` — the method whose contract promises it can never fail the bill — and `RunLegislationPipelineJob`'s catch-all rescue turned that into a run-killing `StageError`.

`#event_ids_for_matter!` is the one place a matter's EventIds come from — `Matters/<id>/Histories` -> `MatterHistoryEventId`, mirroring the working Python predecessor (`legislation/.archive/fetch_hearings.py:139-153`), never `Matters/<id>/Events`, which is not a real Legistar sub-resource (see `docs/explanation/hearing-fetch-pipeline.md` for the history of that mistake). It RAISES the Legistar error classes rather than swallowing them, because its two callers handle failure differently and both have to keep working: `#call_discover` fails the bill on a real transport or 5xx error, while `#event_ids_for_matter` (no bang) falls back to "no events" because attachment discovery may never fail the bill. Fetching once here and deciding what a failure means at each call site is what stops those two policies from drifting into two separate `Histories` fetches.

`#memoize_no_events` is the only place that caches "this matter has no reachable events" — so the several rescue branches that reach that conclusion cannot disagree about whether they wrote it down — and, for the same reason, the only place that records the `Histories` collection as unread.

A 2xx body that parsed fine but is not an `Array` reaches "this matter has no hearing events" without passing through any rescue, so it is the one give-up path you miss if you only look at rescue blocks. Same consequence as the rescues elsewhere in `#event_ids_for_matter!`: the whole event-items half of discovery is skipped.

`#fetch_matter_attachments` covers collection (a), `Matters/<id>/Attachments`, with the same tolerance as `FetchBillsService#fetch_attachments` — a non-2xx or non-JSON response turns into an empty list instead of raising.

## Why a malformed attachment id still surfaces as a failed download, not a dropped record

`#keep_entry?`: an entry whose id will not coerce carries no verdict.

`#keep_entry?`: an entry whose id will not coerce carries no verdict — it is KEPT so `#normalize_attachment_entry` can record it as a failed download, the standing contract that malformed entries still surface alongside their siblings.

`#normalize_attachment_entry` turns one raw attachment (from either collection) into the shared record shape that no longer cares which endpoint it came from. A malformed id gets `download_status` `"failed"` plus a length-limited error message and can never be turned into a file path (its id is `nil`) — but it is NOT dropped from the returned array, so its sibling attachments still show up.

## fetch_event_item_matter_attachments: collection (b)'s request shape

For each unique EventId, `#fetch_event_item_matter_attachments` requests `Events/<id>/EventItems` with a STRING-keyed `"Attachments" => 1` param.

For each unique EventId, `#fetch_event_item_matter_attachments` requests `Events/<id>/EventItems` with a STRING-keyed `"Attachments" => 1` param — a Symbol key would get a `$` prefix from `Legistar::Client#odata_params`, and Legistar rejects `$Attachments` with HTTP 400 (checked against the live API) — filtered to `EventItemMatterId == matter_id_int`, reading `EventItemMatterAttachments` and not `EventItemAttachments`, a mix-up the old Python version warned about in its own notes.

## Attachment deduplication and provenance ordering

`#dedupe_attachment_entries` drops duplicates by `MatterAttachmentId` across the two attachment collections (`Matters/<id>/Attachments` and the event-nested `EventItemMatterAttachments`).

`#dedupe_attachment_entries` drops duplicates by `MatterAttachmentId` across the two attachment collections (`Matters/<id>/Attachments` and the event-nested `EventItemMatterAttachments`), which share one id space, so a repeated id names the same document. `#dedupe_key` groups on the CLEANED-UP id (via `#coerce_attachment_id`) — the same value used as the key by the verdict map, the classification cache row, and the sidecar file name (`#attachment_basename`) — rather than the raw value. Grouping on the raw value let `38947` and `"38947"` both survive as two records that then fought over one `attachment-38947.{pdf,txt}` pair: the second download overwrote the first, and `#compose_testimony_from_disk` read that one sidecar twice, so the text appeared twice inside `extracted_testimony`. An id that cannot be cleaned up has no identity at all, so it gets its own per-object dedupe key (`[:uncoercible, entry.object_id]`) rather than being grouped with its equally broken siblings under one `nil` key, which would have dropped all but one — every malformed entry must keep showing up as its own failed download.

Within a duplicate group, `#entry_provenance_rank` picks a winner by an explicit ordering — event-associated entries first, then the lowest event id, then the lowest event-item id — rather than `group.find`, which took whichever event-associated entry happened to come first and made the recorded `event_id`/`event_item_id` depend on the order Legistar returned `Histories` in. Which entry wins no longer decides the attachment's identity (see `#attachment_basename` below), but the same set of responses should still produce the same origin details in the artifact. A MISSING `event_item_id` sorts LAST within its event, not first (`PROVENANCE_RANK_MISSING = MATTER_ID_MAX + 1`, strictly greater than any real event-item id): ranking it `0` meant an entry Legistar had not tied to a specific agenda item beat a sibling on the same event that did have one, so the artifact kept the vaguer of the two.

`#event_item_attachment_entries` runs the raw `EventItemId` through `#coerce_attachment_id` — the same coercion the `PROVENANCE_RANK_MISSING` sentinel's own comment claims for it — rather than a bare `is_a?(Integer)` check. A bare type check once let an `EventItemId` above `MATTER_ID_MAX` through unclamped, and because `PROVENANCE_RANK_MISSING` is that bound plus one, an id past it would sort AFTER the "no id at all" sentinel and invert the tie-break the comment above promises. It only decides which duplicate's origin details reach the artifact, but it decided that backwards until the coercion was applied consistently.

## Why a document's file name carries only its id

`#attachment_basename` names sidecar files `attachment-<id>.{pdf,txt}` — the cleaned-up integer id alone, with no `source_endpoint` in the name.

An earlier version assumed a `MatterAttachmentId` and an `EventItemMatterAttachment` id came from different Legistar id spaces and put the source endpoint in the file name to keep them apart. The live recording says otherwise: all 28 `MatterAttachmentId`s of matter 10122 appear unchanged inside the nested `Events/5065` set (`spec/cassettes/legistar_testimony_endpoint_probe.yml`). Including the endpoint in the name also meant the name changed whenever `#fetch_event_item_matter_attachments` fell back to an empty list on a per-event fetch failure — orphaning the PDF/TXT pair and reintroducing the bug where a re-fetch failure silently lost earlier testimony.

"The id alone identifies an attachment" holds only WITHIN the Baltimore Legistar account, the only one that exists today (`Legistar::Client::DEFAULT_CLIENT`). It is a single-jurisdiction assumption, and the key must change before a second Legistar jurisdiction is added — see the note on `Legislation::Paths.attachments`, which covers the classification cache keyed the same way.

## fetch_hearing_event: an unrecorded response shape, and the only 404 signal in the pipeline

`#fetch_hearing_event` fetches `Events/<id>` — the resource that carries `EventDate`/`EventTime`/`EventLocation`/`EventBodyName` — NOT `Events/<id>/EventItems`, which is the attachment collection.

That response shape was checked by hand against event 5065 and is NOT in `spec/cassettes/legistar_testimony_endpoint_probe.yml`, which records `Events/5065/EventItems` (a different resource) and nothing for the bare event. The shape is held in place only by hand-written test stubs, not by a recording; add the `Events/5065` request the next time that cassette is re-recorded.

It is rescued per event, mirroring `#fetch_event_item_matter_attachments`: one unreadable event degrades to "no row for that event" rather than discarding the sibling hearings, which are real data. A total Legistar outage has already raised out of the `Histories` fetch in `#call_discover` before this runs, so this rescue cannot mask one.

A 404 here is the ONLY signal in the whole pipeline that an EventId taken from `Histories` points at nothing — Legistar sub-resources answer `200 []` for an unknown parent (see `docs/explanation/legistar-client-design.md`), so `#fetch_event_item_matter_attachments` cannot tell "this event is gone" from "this event had no agenda items" on its own. This request already happens for every event id, so the answer costs nothing extra; it is written down (`#mark_event_unswept`) rather than thrown away.

## Why a 5xx or transport failure on Events/<id> is NOT recorded as unswept

`#fetch_hearing_event` rescues `Legistar::Client::HttpError` and marks the event unswept only when the status is 404.

A 5xx or a transport blip on this DISPLAY resource (`Events/<id>`) says nothing about whether `Events/<id>/EventItems` — the separate attachment-bearing resource — can be read; that fetch happens separately and records its own failure on its own terms. Only a 404 on the bare event is proof the event itself does not resolve upstream, and this method may only report what it actually established.

## matter_id: why it is coerced strictly, twice

`#coerce_matter_id!` (raising) and `#coerce_attachment_id` (nil-returning, never raising) enforce the same limits: a strict positive `Integer`, at most 10 digits, at most `MATTER_ID_MAX` (`2**31 - 1`).

`matter_id` flows into the Legistar URL path, and because its value can come from a file on disk (`metadata.json`) an operator controls, a crafted value could smuggle in path segments (`../`, `1?override=bar`) and reach an unintended Legistar endpoint — a bare `/\A\d+\z/` pattern would still accept an arbitrarily long digit string, which an operator-edited `metadata.json` could carry as a multi-MB blob; production Baltimore Matter IDs are 6-7 digits, well under 2^31.

The two coercion methods differ only in failure behavior, matching how their callers must behave: `#coerce_matter_id!` raises `BillProcessingError` because a malformed `matter_id` should fail the whole bill explicitly rather than reach a confusing 404 against an unintended endpoint. `#coerce_attachment_id` returns `nil` instead, so one malformed attachment id or event id records a per-record failure and lets discovery carry on rather than failing the whole bill.

`#lookup_matter_id_from_metadata` reads the `matter_id` `FetchBillsService` wrote to `metadata.json` under `legislation/bills/raw/<id>/` — there is no `matter_id` column on `Bill` itself, so the Legistar id lives on disk only. The external_id is turned into a safe path segment via `Legislation::Paths.bill_metadata_file` the same way `#coerce_matter_id!` cleans up the matter_id it validates. The "file missing" error message names the STAGE that writes the file (fetch-bills) rather than just the path, because a bare path reads as a fault in fetching hearings when the fix is to run fetch-bills first. The "key missing or uncoercible" error likewise stays distinct from "file missing": `Legislation::BillMetadata.matter_id` returns `nil` both when the file is unreadable and when the `matter_id` key is present but holds a non-Integer, non-String value (a Float, Array, Hash, or boolean from a hand-edited file) — calling that case "unavailable" would be wrong for a key that is very much there.

## The three discovery counts, and why they can look like the same number

`#discovery_census` reports three counts that are easy to conflate:

- **`found`** — the pre-filter union of both attachment collections, every
  row either one returned, tracked BEFORE the `.pdf` gate so `truncated`
  compares against the right baseline (see below).
- **`kept`** — PDF candidates after `MAX_ATTACHMENT_CANDIDATES` truncates
  the list, but BEFORE the name rules and the verdict cache run. On any
  bill carrying bill text or hearing logistics it is LARGER than
  `attachments`, because `Testimony::NameRules` rejects those without them
  ever becoming records.
- **`recorded`** — the length of the `attachments` array beside this
  census, the only one of the three that can be reconciled against it: the
  records that were downloaded and extracted, whether their text composed,
  failed, or was denied at stage 3.

`truncated` (`@discovery_pdf_candidates > kept`) is computed against the PDF-candidate count, not `found`: `found` includes rows the `.pdf` check would have thrown out anyway, so comparing against it would report `truncated: true` for a bill that dropped no testimony at all — one image alongside nine kept PDFs, say. The `.pdf` gate itself runs BEFORE the candidate cap for the same reason, in the other direction: applying the cap to the raw union let a non-PDF consume a candidate slot and push a real testimony PDF off the end (on a 260-attachment matter with 60 images, 60 testimony PDFs beyond index 200 were dropped even though the 200 PDFs alone would have fit the cap). Gating first makes `MAX_ATTACHMENT_CANDIDATES` bound what its name says: candidates that can actually become testimony. `events_unswept` and `collections_unswept` are always written, never conditional, so a consumer never has to guess whether "no unswept events" means "none" or "this artifact predates the key".

## Truncation drops attachments by accident of order, not by value

Both the union truncation and the `MAX_ATTACHMENT_CANDIDATES` cap drop attachments by accident of ITERATION ORDER (matter attachments first, then event items per event), not by value.

Both the union truncation and the `MAX_ATTACHMENT_CANDIDATES` cap drop attachments by accident of ITERATION ORDER (matter attachments first, then event items per event), not by value — so what is lost is arbitrary, and a log warning used to be the only trace. An operator looking at a 200-attachment bill had no signal that evidence had been dropped, on the one surface built to explain missing testimony, which is why the count is now recorded on both the artifact and the admin mirror.

An earlier version of the `.pdf` gate's rationale cited a specific `.jpg` by GUID in the reference cassette as evidence non-PDFs really do show up in the union. That file is in no cassette in this repository, and neither is the row count that came with it. Legistar imposes no file-type restriction — its schema carries `MatterAttachmentIsHyperlink` for exactly that reason — so the gate is correct whether or not the recording happens to hold a non-PDF; the ORDERING (before the candidate cap) is what makes it correct, not that recording. What the recording holds is measured by the cassette examples in `spec/services/legistar/attachment_url_spec.rb`; no count is restated here, because a restated count is a fact with nothing behind it.

`#truncation_mirror_entry` is the half of the same story the operator sees: it rides on the existing failure list (`download_status != "succeeded"`) so no new browser code is needed for it to appear.

## Legislation::BillMetadata.matter_id's own validation

`Legislation::BillMetadata.matter_id` reads the Legistar `matter_id` that `FetchBillsService` writes into each bill's `legislation/bills/raw/<external_id>/metadata.json`.

This folds together a read that `FetchBillsService` and `FetchHearingsService` each used to do for themselves.

`Legislation::BillMetadata.matter_id` reads the same `metadata.json` key covered above and does its own validation before handing a value back, separately from `#coerce_matter_id!`'s validation of the value it receives.

The `external_id` and `sway_locale` arguments are each run through `Legislation::Paths`'s non-raising `_segment` checks before the file is even opened. Returning `nil` rather than raising is the promise this method makes, so an `external_id` that cannot be used in a path gets the same answer as a missing file — the two callers, `FetchBillsService` (which skips the bill) and `FetchHearingsService` (which raises `BillProcessingError`), each supply their own meaning for "missing" on top of this shared `nil`.

An operator can edit `metadata.json`, so the `matter_id` key could hold any JSON value. Handing it back unchecked would make the declared return type `(Integer | String)?` untrue. Narrowing right here, where the untrusted file is read, is what lets both this method's and its callers' type signatures stay specific — a `String` is still allowed through, since `#coerce_matter_id!` accepts a digits-only `String` on purpose.

A `String` value has to LOOK like an id, not merely be a `String`. Letting `"not-a-number"` through made this method's promise — `nil` for anything a caller can't use — untrue for the one caller with no check of its own: `FetchBillsService`'s backfill hands the value straight to `Legistar::Client`, whose own check raises an error the stage doesn't catch per bill, so one hand-edited file ended the run for every remaining bill. The bound reused here is `Legistar::Client::ID_MAX` itself, the same `2**31 - 1` ceiling `#coerce_matter_id!` enforces (`MATTER_ID_MAX` above), rather than a second copy of the number, so this door and the client it feeds cannot drift apart.

Reads, not only writes, are guarded against filesystem errors (`JSON::ParserError`, `SystemCallError`, `IOError`): an earlier pass in this subsystem guarded every WRITE but missed both reads, and `path.exist?` leaves a gap of its own — the file can disappear between the check and the read. Returning `nil` on any of these sends `FetchHearingsService` to its own `BillProcessingError`, costing one bill; raising instead would reach `RunLegislationPipelineJob`'s catch-all and fail the whole run over one file.
