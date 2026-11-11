---
lat:
  mode: explanation
---

# RunLegislationPipelineJob internals

This collects the design decisions inside `RunLegislationPipelineJob` not already covered by its other extracted docs (see `related` above).

## Why INLINE_DISPATCH_STAGES and the boot-time integrity check exist

Stages with `nil` in `STAGE_SERVICES` have no service class — they are dispatched inline by `execute_bill_level_service`.

The set is spelled out in `INLINE_DISPATCH_STAGES` so the class-load integrity check below it can catch drift between the two lists (same pattern as `STAGE_STATUS_TO_DAG_NAME` in `legislation_pipeline_run.rb`).

That boot-time check exists because, without it, the bug would only show up as a `StageError, "RUN_LEVEL stage has no service class"` the first time the affected stage actually ran — the check catches it at boot instead.

## Why fetch_law runs before extract_text in DAG_ORDER

`fetch_law` runs BEFORE `extract_text` so that `ParseSectionsService` and `GenerateDiffsService` can read `LawSection` rows. This is purely about call order — the state machine already declares every event these stages need.

## Why ORIGIN_VALUES exists and unknown values are logged, not rejected

The docs used to say only "fresh|resume" while the code accepted any String — `SeedBill` passes `origin: "seed"`, which quietly flowed through dispatch as if it were "fresh".

The orchestrator only branches on `origin` at the `normalize_for_resume` call, so unknown values do no harm — but logging them makes drift between callers and `ORIGIN_VALUES` visible in the activity log.

An unknown origin gets a structured log line, not an error, so hand-rolled callers outside this repo keep working.

## Why @origin is kept around

`@origin` is kept around so the bill-level progress logs can label seed runs.

## Why the auto-include set is computed once, before the stage loop

The AUTO-INCLUDE set is computed ONCE per run, BEFORE the stage loop.

It never changes during a run, and computing it inside the loop would repeat the dependency-graph walk ~830 times at 166 bills times 5 bill-level stages. Operator-checked stages are the symbols already in `run.stages`; auto-included stages are whatever the dependency closure adds on top of that selection. `run_bill_level_stage` carries these into the per-bill loop.

## Why the per-stage InvalidTransition rescue is narrow

The `InvalidTransition` rescue inside the stage loop is deliberately narrow: it wraps only the state-machine event calls inside that block.

An older version rescued at the top of `perform` and quietly logged-and-returned — on the operator's "Resume Run" path that looked like success (HTTP 200) while the run sat stuck and the Solid Queue lock stayed held until its duration expired. The per-stage rescue records the invalid transition in the activity log AND fails the run, so the operator-facing UI shows the failure right away.

It re-raises as `StageError` so the outer `StageError` rescue routes through `handle_run_failure` -> `force_fail!`. The operator then sees a run that ended in failure instead of one silently stuck, and the Solid Queue lock releases when the job finishes.

## Why the auto-include context is passed through Pipeline::Current and cleared in ensure

"Why was this stage auto-included" details are passed to the activity logger through `Pipeline::Current`.

It's set ONLY for AUTO-INCLUDED stages; OPERATOR-CHECKED stages leave the context nil so the logger's payload shape stays unchanged.

The context is cleared no matter how the stage block exits (success, exception, or raise -> rescue -> raise), in an `ensure` block. Solid Queue worker threads keep their own `Thread.current` state; leaving the context set would leak one auto-included stage's details into the next operator-checked stage in the same loop.

## Why the operator-abort path logs and exits cleanly instead of calling handle_run_failure

The operator hit Force-Fail mid-run.

By the time `perform`'s `OperatorAbortError` rescue runs, the run is already in a terminal state (failed / cancelled) — calling `handle_run_failure` would try `run.force_fail!` from `:failed`, raise `StateMachines::InvalidTransition`, and write a noisy audit-log entry the operator never asked for. It logs the abort and exits cleanly instead; Solid Queue releases the concurrency lock and the worker is free for the next run.

It intentionally does NOT raise — the run row is already terminal and the activity log already carries the operator's force_fail entry from the `PipelineRunsController` action.

## Why the outer InvalidTransition rescue exists separately from the per-stage one

This rescue ONLY catches an `InvalidTransition` raised OUTSIDE the per-stage block — i.e.

from the `start_running!` / `mark_succeeded!` calls at the top and bottom of `perform`. It fails the run and re-raises so it terminates loudly; an older version silently returned success here, which left runs stuck with no visible error.

## Why service_mode_for is a named method

The dispatch rule — operator-checked -> `:discover`, auto-included -> `:backfill_missing` — lives in a named method, `service_mode_for`, so the rule is explicit and easy to find.

## Why bills_triggering_auto_include returns an empty array for RUN_LEVEL stages

`bills_triggering_auto_include` lists the `bill_external_ids` that caused a stage to be auto-included.

For BILL_LEVEL stages, that is every `pipeline_run_bill` whose Bill is missing the stage's artifact. For RUN_LEVEL stages (`fetch-bills`, `fetch-law`) the auto-include applies to the run, not to individual bills, so the array is empty — the orchestrator still sets the context (stage + reason) so the logger records the auto-include.

## Why run_run_level_stage rewraps a stray BillProcessingError-shaped failure as StageError

Run-level stages re-raise run-wide discovery or adapter failures as StageError while bypassing isolated per-row errors.

A run-level stage (`fetch_bills`, `fetch_law`) must end the run when run-wide discovery or adapter operations fail, so an aborted stage is never recorded as succeeded.

When `RunLegislationPipelineJob#run_run_level_stage` rescues `BillProcessingError`, it inspects the message. If the error represents a run-wide failure — indicated by starting with `"fetch_bills"` or `"fetch_law"`, or containing `"No active session found"`, `"Congress.gov HTTP"`, or `"no bills were discovered"` — it re-raises `StageError` with the message. This causes `handle_run_failure` to mark the stage and run as failed. Only isolated per-row errors (such as malformed date parsing on a single row) bypass stage failure with a logged warning, allowing execution to proceed.

## Inside run_bill_level_stage

Execution sequence and error handling applied when iterating over individual bill records within bill-scoped pipeline stages.

### Why the environment is preflighted before the per-bill loop

`preflight_stage_environment!` checks run-wide config for a stage before its per-bill loop starts.

Today only `extract_text` depends on an env var at construction time (`TESSDATA_PREFIX`, for the mutool OCR fallback). `TESSDATA_PREFIX` is read at `MupdfExtractor.new` — if it's unset, EVERY bill fails the same way and the failure budget aborts after 5 bills with a misleading per-bill error. The dedicated `MupdfExtractor.preflight!` class method is called instead — it reads ENV only, no filesystem access — rather than constructing an extractor against a placeholder path, which would tie the check to constructor side effects.

### Why stage_key is computed once before the loop

`stage_key` is computed ONCE before the `find_each` loop rather than inside it.

At 166 bills x 5 bill-level stages = 830 iterations, recomputing it every time would be wasted CPU. (Auto-include selection is already resolved in `perform` and arrives as the `auto_included` boolean.)

### Why the run is reloaded on every bill iteration

An operator's Force Fail POSTs `/pipeline_runs/:id/force_fail`, which fires the model's `force_fail` event and flips status to `:failed`.

This job used to keep churning through bills because it never re-read the run row inside this loop — the operator saw "Force Fail" succeed, then watched bills keep processing for several more minutes. Reloading every iteration costs one cheap SELECT per bill (typically 200 bills or fewer) and lets the operator's abort take effect within a single bill's processing window.

### Why the artifact-aware skip gate only applies to auto-included stages

The artifact-aware skip applies ONLY when the stage was AUTO-INCLUDED by the `download_missing_assets` closure.

Operator-checked stages run unconditionally for every bill — if the operator ticked the box, honor it regardless of artifact state. (This gate is separate from `stage_already_succeeded?`, which handles resuming this run. Both must fire — neither replaces the other.)

A skipped bill is still walked through `start_running!`/`mark_succeeded!` so the per-bill row lands in a finished state; otherwise the stage-local success accounting (the `json_extract` count) would need a third "skipped" branch on top of its existing "succeeded" + "skipped" ones.

### Why the two nested record_stage_result rescues exist

Both the `BillProcessingError` branch and the generic `rescue => e` branch wrap their `record_stage_result` call in its own `begin/rescue ArgumentError`.

This guards against `record_stage_result`'s stage allowlist raising inside the recovery branch — its `ArgumentError` on an invalid stage symbol would otherwise escape and hide the ORIGINAL error (`BillProcessingError` or the generic `StandardError`). Logging and continuing lets the budget accounting and the `StageError` raise below carry the real failure.

### Why a bare StandardError records a failure entry before re-raising

A non-`BillProcessingError` (a `NameError` from a typo, an OS-level exception, anything else) used to escape this block WITHOUT recording the per-bill failure to `stage_results`.

On resume, `stage_already_succeeded?` found no entry and the same bill was retried forever (the consecutive-failure budget is a local variable, so every fresh `perform` call reset it to 0).

So the failure entry is recorded BEFORE re-raising as `StageError`, so resume can tell "stage never attempted" apart from "stage tried and crashed." The `StageError` raise still routes through `handle_run_failure` to mark the run failed.

## Inside execute_bill_level_service and execute_extract_text

Service invocation boundaries, status persistence, and text extraction error trapping for individual bill artifacts.

### Why only ExtractionFailed is a per-bill failure

Only `MupdfExtractor::ExtractionFailed` is caught as a per-bill failure.

Only `MupdfExtractor::ExtractionFailed` is caught as a per-bill failure — `MissingTessdataError` is a run-wide config failure raised at `MupdfExtractor.new`; it MUST escalate to `StageError` and is checked up front in `preflight_stage_environment!`.

### Why a bad LLM response converts to a per-bill failure

A malformed, truncated, or schema-invalid LLM response (`GenerateBillSummaryJob::BillSummaryError`) is a PER-BILL failure.

It's converted to `BillProcessingError` so the tolerant per-bill branch marks just this bill failed and honors the consecutive-failure budget — instead of the catastrophic `StandardError` branch force-failing the whole run because one bill's LLM output was bad.

### Why a missing PDF is a skip, not a failure

A Legistar matter with no PDF attached (attachment-less resolutions, for example) is not a per-bill failure — it's a legitimate skip.

Treating those as `BillProcessingError` would trip the 5-in-a-row failure budget whenever Legistar clusters no-PDF bills (resolution batches commonly do), aborting the whole run for bills that DO have PDFs and would otherwise succeed.

"No PDF on disk" gets its own `skipped` status. Skipped is NOT counted toward `consecutive_failures` and IS counted toward `stage_succeeded_count`, so the "all bills failed" stage-local check trips only when everything genuinely failed.

### Why the bill is resolved first in execute_extract_text

THE BILL IS RESOLVED FIRST, AND THAT ORDER MATTERS.

The PDF's path now includes the bill's `sway_locale`, so finding it needs a resolved bill. When `#locate_pdf` did that lookup for itself it answered nil for a row that names no bill — and the caller reads nil as "this bill has no PDF", a SKIP that costs nothing and is not counted as a failure — a row naming a bill that does not exist, or an `external_id` two jurisdictions share, quietly became "nothing to do here" instead of a per-bill error an operator can see. Resolving here restores that signal: `#resolve_bill!` raises `BillProcessingError`, which fails this one bill and lets the run go on. Only a genuinely missing FILE is a skip now.

### Why bill.update! replaced a double nil-guard

This used to be `bill&.update!(extracted_text: text) if bill.respond_to?(:extracted_text)` — two nil-guards that both fail open.

`nil.respond_to?(:extracted_text)` is FALSE, so when the lookup refused, the update was skipped, the text file was written anyway, and the stage was recorded "succeeded" for a bill whose `extracted_text` was still empty. `Pipeline::ArtifactPresence` then saw the file and agreed the stage was done, `stage_already_succeeded?` made resume skip it, and nothing ever came back to fix it.

`#resolve_bill!` runs at the top of the method, BEFORE the extraction and before the write, so a bill that cannot be resolved leaves no file claiming otherwise.

### Why the output path is built from the resolved bill

The path comes from `Legislation::Paths`, which coerces both the `sway_locale` name and the `external_id` into single safe path segments.

The path comes from `Legislation::Paths`, which coerces both the `sway_locale` name and the `external_id` into single safe path segments — important because this `File.write` is one of the two places where a hostile `external_id` could otherwise write to an arbitrary path.

Both halves come off the RESOLVED bill. `PipelineRunBill` carries only `bill_external_id`, which does not identify one bill (bills are unique on `(external_id, sway_locale_id)`), so a path built from it alone filed two jurisdictions' text under one name.

### Why a disk write failure converts to a per-bill failure

A disk failure here must cost this bill, not the run.

Without the conversion a `SystemCallError` reaches `#run_bill_level_stage`'s catch-all, which raises `StageError` and force-fails every remaining bill. It matters more here than at most write sites: the `update!` above has already committed, so the database would say the stage produced its text while the run died claiming the stage failed.

## Why resolve_bill passes no locale

`external_id` alone does NOT identify a bill — the bills unique index is `(external_id, sway_locale_id)`.

This lookup feeds the extracted-text write in `#execute_extract_text`, and an unscoped version once wrote one jurisdiction's bill text onto another jurisdiction's row.

No locale is passed: `bill_run.legislation_pipeline_run` would re-query per bill inside a `find_each` loop (Bullet, the N+1-query detector, must stay green), and the run has no locale of its own anyway — `legislation_pipeline_runs` has no `sway_locale_id` column, so when the id is ambiguous, the lookup refuses (returns nil), which is the safe choice.

## Why resolve_bill! centralizes the nil check for all three dispatch arms

A nil from `#resolve_bill` means the lookup DECLINED — `external_id` is not a key (the unique index is `external_id` + `sway_locale_id`), so an id shared by two locales is ambiguous and the lookup refuses rather than guesses.

Only the `else` arm used to treat that nil as a failure; `:summarize` produced no summary and `:extract_text` stored no text, yet both recorded "succeeded", making `stage_already_succeeded?` skip the bill on every later resume.

It's a method rather than a repeated guard because that divergence was the bug: three arms, only one of which had the check. Now none of them can be written without it.

## Why record_stage_result takes a reason: kwarg

The `reason:` kwarg records why a stage was skipped (e.g.

"artifact_present" — the bill already has this stage's artifact, so an AUTO-INCLUDED stage skipped it). It's persisted to the `stage_results` JSON so the operator-facing per-bill grid and activity log can show the skip reason instead of leaving "stage didn't run, why?" unanswered.

## Why locate_pdf calls the non-raising resolve_bill

The PDF lives under `<bills_raw>/<sway_locale>/<external_id>/`, so finding it needs the bill, not just the `external_id` `PipelineRunBill` carries.

The NON-raising `#resolve_bill` is deliberate. Its caller turns a nil return into `:skipped_no_pdf`, which is not counted toward `consecutive_failures`, and that is the right answer for a bill the lookup declined: an ambiguous `external_id` names no single artifact directory, so there is no PDF to find. Using `#resolve_bill!` here would convert those bills from skipped to failed and change which runs trip the "all bills failed" check.

`locate_pdf` takes the RESOLVED bill, not the run row. Both halves of the path — the `sway_locale` name and the `external_id` — come off the bill, because `PipelineRunBill` carries only `bill_external_id` and that does not identify one bill. Taking the bill also keeps "no bill" and "no PDF" apart: the caller resolves first and fails the bill, so a nil from here means only that the file is missing.

## Why normalize_for_resume writes the status column directly, bypassing the state machine

The status write lives on the model, beside the rule it is the one exception to: every other status change goes through the state machine, which writes the Activity Log row and sends the cable message.

This write cannot, because no event means "nobody finished this stage," so the model does both by hand. Writing the column from here skipped them.

## Why normalize_for_resume also resets non-succeeded stage rows

Defensive: also re-opens any non-succeeded stage row so a re-entry by `start_X!`/`complete_X!` does not collide with a stale row.

Only rows for the stuck stage that are NOT already `"succeeded"` are reset; succeeded rows must stay so `stages_to_run` keeps skipping them.

## Why stage_name_for_status delegates and never raises

Maps a stuck `*ing_*` status back to the DAG stage name (e.g.

`"fetching_law"` → `"fetch_law"`, `"parsing_sections"` → `"parse_sections"`). The status column uses `<verb-ing>_<noun>` names while `pipeline_run_stages.stage_name` uses `<verb>_<noun>` (`DAG_ORDER` form). Returns nil if no mapping is found — never raise here, the `normalize_for_resume` caller is best-effort.

Delegates to `LegislationPipelineRun::STAGE_STATUS_TO_DAG_NAME`, the single source of truth (kept next to `PHASE_52_STAGE_STATES` and guarded by a class-load integrity check), so this mapping cannot drift from the model's.

## StageError vs. BillProcessingError

`StageError` is raised when a whole pipeline stage cannot go on at all — for example, the Legistar bill-list endpoint keeps returning a server error after every retry.

It is not the same as `BillProcessingError`, which is about a single bill. When the pipeline runner catches a `StageError` it marks the stage as started (`run.public_send(:"start_#{stage}!")`) and then force-fails the whole run. A `BillProcessingError` lets the run continue and only marks the one bad bill as failed.
