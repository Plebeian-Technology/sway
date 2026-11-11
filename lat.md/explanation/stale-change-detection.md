---
lat:
  mode: explanation
---

# What makes a bill summary stale

`BillLlmProvisioning#stale_change` returns the change that left the summary out of date, as a `[kind, moment]` pair, or `nil` when nothing has.

This is the single computation behind both `#stale?` and the `stale_change_kind` / `stale_change_at` values sent to the browser (see [[docs/explanation/bill-provisioning-payload.md|The bill provisioning JSON payload]] for how those are wired into `to_builder`).

## Why this is one computation, not two

The screen has to say WHICH change overtook the summary; `#stale?` has to say WHETHER one did.

Answering those in two places is exactly how the marker came to announce staleness and then describe the wrong cause: `#stale?` gained a testimony arm and the marker went on reading `diff_generated_at` alone, so a summary overtaken by testimony ten hours ago read "pipeline data updated 21 days ago" — a sentence an operator who knows the pipeline has not run for three weeks would reasonably ignore.

`#stale?` is derived from `#stale_change`, and a third thing that can overtake a summary reaches the screen by being added to `#stale_change`.

## Both moments are measured against the same llm_generated_at

Measuring the two candidate moments — `testimony_fetched_at` and `diff_generated_at` — against different moments would quietly get staleness wrong.

Taking the newer of the two WITHOUT comparing each against `llm_generated_at` first would be wrong in a different way: a diff newer than the testimony can still be older than the summary, and naming it would quote a moment that overtook nothing.

## Picking a winner

When both a testimony change and a pipeline-data change apply, the newer one wins — it is the most recent thing to overtake the summary. A tie goes to testimony, the more specific of the two.

## What the marker used to read, and why it changed

`diff_content` and `diff_generated_at` are no longer sent to the browser at all (see [[docs/explanation/bill-provisioning-payload.md|The bill provisioning JSON payload]] for the removal).

The out-of-date marker's one reader of `diff_generated_at` was retired at the same time it started reading `stale_change_at` instead, because the diff is only ONE of the two things that can overtake a summary — quoting it when testimony was the actual cause is exactly the bug described above.

## The two change-kind words are spelled once on each side

`BillLlmProvisioning::TESTIMONY_CHANGE` and `::PIPELINE_DATA_CHANGE` (Ruby) and `TESTIMONY_CHANGE` / `PIPELINE_DATA_CHANGE` in `app/frontend/components/admin/creator/llm-summary/staleChange.ts` (TypeScript) are the same two words.

`BillLlmProvisioning::TESTIMONY_CHANGE` and `::PIPELINE_DATA_CHANGE` (Ruby) and `TESTIMONY_CHANGE` / `PIPELINE_DATA_CHANGE` in `app/frontend/components/admin/creator/llm-summary/staleChange.ts` (TypeScript) are the same two words, spelled once for the server and once for the browser — the same arrangement `OPERATOR_PASTE_PROVIDER` uses (see [[docs/explanation/operator-paste-provenance-marker.md|Why pasted summaries are marked with one shared provider string]]) and for the same reason: the server produces `stale_change_kind` as one of these two strings, and the browser's `staleChangeLabel` switches on it to choose the subject noun on the out-of-date chip. A hand-typed copy on either side is exactly how the two could drift apart silently.

## staleChangeLabel's fallback wording

The words on the out-of-date chip.

The fallback covers a row the server says is out of date while naming no moment. The server cannot produce that pair — `#stale_change` hands back the kind and the moment together or neither — so this is honest about not knowing rather than guessing a cause.

## Testing the out-of-date marker in a browser

`spec/system/admin_summary_stale_marker_spec.rb` pins a hands-on test.

That hands-on test ended PARTIAL — the reason it could not finish is the reason these are Capybara examples rather than instructions for a person to redo. The server side was measured by hand and works: a re-fetch that brought newer testimony moved `testimony_fetched_at` and flipped the flag, and a re-fetch of byte-identical testimony correctly did not. What could not be judged by hand was whether the marker turns up ON SCREEN by itself, because the pipeline-busy notice was stuck over it (see [[docs/explanation/summary-tab-pipeline-running-poll-fallback.md|the Summary tab poll fallback]]). The lesson from stopping there: a test whose evidence is a person happening to look at the right second cannot reliably fail, so it cannot reliably pass — these examples wait deterministically with nobody watching.

### The fixture's two hand-written moments

`up_to_date_summary` writes `diff_generated_at` and `testimony_fetched_at` by hand rather than through the `:with_diff_content` trait, because that trait stamps `diff_generated_at` with the current time.

`up_to_date_summary` writes `diff_generated_at` and `testimony_fetched_at` by hand rather than through the `:with_diff_content` trait, because that trait stamps `diff_generated_at` with the current time — which would make the row out of date the moment it is created, for the OTHER reason, and no example could then tell the two staleness causes apart. The bill fixture itself sets `extracted_text` rather than relying on `diff_content`, for the same reason covered in [[docs/explanation/bill-summary-call-preconditions.md|bill-summary-call-preconditions.md]]: `extracted_text` is what `BillSummaryPromptBuilder` reads, so it is what makes a regeneration runnable at all.

### Why the first example keeps a pipeline run going for the whole wait

"Raises the out-of-date marker on its own when newer testimony lands" leaves a `LegislationPipelineRun` running for the whole waiting period, which is what keeps the five-second poll timer mounted on this tab.

"Raises the out-of-date marker on its own when newer testimony lands" leaves a `LegislationPipelineRun` running for the whole waiting period, which is what keeps the five-second poll timer mounted on this tab — the same reason spelled out in [[docs/explanation/summary-tab-pipeline-running-poll-fallback.md|summary-tab-pipeline-running-poll-fallback.md]]. It is also the real situation this pins: testimony arrives DURING a fetch-hearings run, with the operator sitting on the Summary tab watching for exactly this. The example's marker assertion also names TESTIMONY, not pipeline data — the pipeline's own moment is two hours old and overtook nothing, so a marker blaming pipeline data would point the operator at the wrong thing, which is the bug this doc describes above.

### Why the second example starts from an already-stale row

"Clears the marker once the summary is made again" starts from an already-out-of-date row, because how the row got there is the first example's job.

The pipeline run is deliberately absent: the Regenerate button is greyed out while one is going, so an absent run is the state an operator can actually act from.

### The queued-job race this example has already hit once

The click that starts regeneration sends the request and returns; the job is enqueued inside that request.

Running the job queue immediately after the click can therefore find it still empty and leave the job unrun, failing the example for a reason that has nothing to do with the marker. This cost exactly that on the sibling example in `spec/system/admin_supplemental_testimony_spec.rb`, so this example waits for the row to say "Queued…" before running the queue.
