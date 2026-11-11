---
lat:
  mode: explanation
---

# BillCreatorPipelineControls mechanics

How BillCreatorPipelineControls decides why the run button is off, and hands that reason to PipelineActionButtons as an accessible notice rather than a title attribute.

## Why runDisabledReason is a named string, not a title on a wrapper div

Each disabled-reason names itself in the caller, not inferred downstream, so a third reason later can't borrow the second's wording.

Previously this reached the button as one boolean with the reason in a `title=` on a wrapper div — invisible to screen readers and to a disabled control. A browser does not show a title for a disabled control, and a title on a wrapper is not a description of the button inside it. That form also covered only one of the two reasons the button can be off: deselecting every stage greyed it out and said nothing at all.

### RUN_DISABLED_NOTICE_ID ties the notice to the button

Ties the notice to the button it explains, using one id because only one run CTA is ever on screen.

The link between the notice and the run button is what a screen reader follows. An id on a notice nothing points at would read as an ordinary paragraph.

### The runDisabledReason prop carries the words, not a boolean

Why the run button is off, in words, or null when it is on.

The caller works this out because the caller holds the reasons; deriving it here from `runDisabled && !isRunning` would silently label a third reason as the second one the day somebody adds it.

## Why stage selection uses two buttons rather than a tick-all box

Selection has three states — none, some, all — and a control that knows only on and off has to misreport the middle one.

Two buttons say what they do, and each greys out when it would change nothing, so all three states stay readable without a half-ticked glyph whose meaning nobody agrees on. Both buttons live means some are ticked, and the count beside them spells it out. Each replaces the whole selection in one call rather than toggling seven stages in turn.

Neither asks for confirmation, deliberately. This card only chooses stages. Run is what starts them, and that is where the cost is explained and where the prerequisite warning already appears, so a confirmation here would confirm the wrong action.

Seven boxes meant seven clicks each way, and every round was a chance to leave one in the wrong state without noticing. Sending the whole list in one call is what makes the bulk buttons safe rather than merely quicker: seven separate toggle calls would each arm the same delayed send, which is the shape that already lost a click on this screen once.

### An auto-included stage does less than the same stage ticked

A stage the panel adds on the operator's behalf runs a reduced form of itself, and the panel says so beside it.

The two used to carry the same name in the same box, which claimed work that was not going to happen. The surprising case, and the one that costs an operator real work, is Fetch bills: added automatically it performs no discovery, so that week's new legislation never arrives — although it will still fetch a bill already named in the run when that bill has nothing saved.

### What an in-flight run mutes

A run in flight mutes the selection controls without disabling any of them, so the greying that remains means only what it always meant.

An in-flight run used to disable the stage checkboxes and both bulk buttons. That cost the operator the ability to line up the next run while watching the current one, which is the natural moment to do it, since a selection changed now applies to the next run rather than this one. It also overloaded the greyed appearance: a bulk button could be grey because it would change nothing, or because a run was under way, and nothing distinguishes those by looking. Muting is opacity paired with aria-busy on the region, because opacity alone reaches no screen reader and can fail contrast on its own.

## Pipeline actions preserve the working address

Starting a pipeline preserves the page's query parameters and submitted stage selection so the return visit reconstructs the controls the operator used.

The return path stays on the selected bill's pipeline page or the all-bills
pipeline page. Query parameters are carried only from a local referring page
with that same path. The submitted stages and download setting override their
older URL values, because a Run click can arrive before the delayed preview
request updates the address. The all-bills return includes `tab_key=pipeline`.
The same return address handles a queued run and a server refusal, keeping
the choices available for another attempt.
Similarly, usePipelineControlsState strips only the parameters it controls via currentAddressWithout so ambient parameters like run_id remain intact across partial reloads.

## The page's control props follow URL precedence

The selected bill and pipeline controls are derived from the URL with path identity taking precedence over a query selection.

[[app/controllers/bills_controller.rb#BillsController#compute_pipeline_controls_state]] returns the bill id as a string, using the path id for an edit page and `bill_id` only on the id-less pipeline page. A missing bill selection becomes an empty string. [[app/controllers/bills_controller.rb#BillsController#selected_pipeline_stages]] discards unknown checkbox names, selects `DEFAULT_PIPELINE_STAGE_KEYS` (every stage except `summarize-bill`, so default runs do not summarize hundreds of bills) when the key is omitted, and selects none for an explicit empty list. Missing `download_missing_assets` defaults to true, and an explicit boolean value is preserved.

## Why an empty stage selection is spelled out on the wire

An empty stage selection travels as a literal empty string query parameter rather than an empty array or an omitted key.

`BillsController`'s pipeline controls action reads `params[:selected_stages]` to determine selected stages. An omitted parameter defaults to `DEFAULT_PIPELINE_STAGE_KEYS`, so unchecking every stage cannot simply omit the key. Furthermore, nested query builders and Inertia serialisation omit empty arrays entirely. Expressing an empty selection requires writing the literal query parameter `?selected_stages=` into the address via `addressWithEmptyList`, which the centralized navigation interceptor preserves across dispatch rather than stripping as a generic cleared parameter. Selecting the default stage set (`DEFAULT_STAGE_KEYS`, which omits `summarize-bill`) omits stage keys from the address and visit data so the server default applies, whereas selecting all stages (including `summarize-bill`) sends the explicit stage list. Because `?selected_stages=` denotes zero stages rather than parameter clearance, `applyNavigationCarryToVisit` skips carrying the `selected_stages` family (`selected_stages` and `stages`) from `currentUrl` when a partial reload includes `selected_stages` in `visit.only` and omits the family from both the destination URL and `visit.data`, preventing a prior non-default URL from overwriting a return to the default stage set.

## Why pipeline controls debounce URL updates

Debouncing URL pushes by 250 milliseconds collapses rapid checkbox interactions into a single network visit without delaying the interface.

When an operator clicks multiple stage checkboxes in quick succession, dispatching an Inertia visit for each click would flood the server with redundant preview recalculations. Debouncing URL pushes batches rapid interactions into a single visit. Meanwhile, local component state flips immediately upon interaction so controls feel responsive rather than delayed.

## Why pending state caches prevent click loss during round trips

Unsent local changes take precedence over arriving server props because a change waiting to be sent is newer than any in-flight response.

When an operator unchecks two stages with a slight pause between them, the first change dispatches a visit while the second change remains queued in the debounce timer. The hook tracks whether an unsent change exists (`changeNotYetSent`). If an earlier server response arrives reflecting only the first change, the hook retains the pending local state rather than allowing the older server response to overwrite the operator's latest selection.

## Why deriving state during render reconciles server responses

Reconciling pending state directly during render drops local overrides when server props arrive, avoiding extra render cycles or side-effect state setters.

When the server's prop update arrives matching or normalizing the operator's selection, the hook clears its pending state directly during render. Comparing current props against previously reconciled props inside render adheres to React's pattern of storing information from previous renders without violating prohibitions on setting state inside effects.

## Why partial parameter updates retransmit full state snapshots

Updating one pipeline control parameter includes the current value of the other parameter so partial updates do not reset unedited settings.

`usePipelineControlsState` manages both `selected_stages` and `download_missing_assets`. When an operator toggles the asset download setting, the dispatched visit carries the current stage selection rather than reverting to mount-time values or defaults. Similarly, changing stage selections includes the current asset download boolean.

## Why subscriptionState is threaded down as a prop

`BillCreatorPipelineLlm` owns the live-updates connection and hands its state down, so one connection feeds both this component's paused banner and the panel's own refreshes.

## Why pickedBillId falls back to "run every bill"

A pipeline run covers whichever bill the page is currently on, chosen with the shared bill picker, while an empty value means running every bill.

### pickedBillIdFor

The `bill_id` for a new pipeline run is read off the shared bill picker `BillCreatorShell` draws above the tabs.

An empty string means the picker is on its "All Bills" entry, and `usePipelineRunActions` turns that into `bill_id: null`, which the server reads as every bill.

It lives here rather than inside `BillCreatorPipelineControls` because two components need the same answer: the controls, which post it, and the failure alert, which tells the operator what the Run pipeline button will cover. Deriving it twice would let the two drift apart.

## Why isRunning checks every non-finished status, not just queued/running

In-flight status covers any non-finished state because a run spends most of its life in a stage-named status rather than queued or running.

Checking only queued and running hid the Force-fail button mid-run.

## Why ForceFailDialog stays mounted when closed

`ForceFailDialog` remains mounted on the page even when closed so it can animate shut when `forceFailOpen` transitions back to false.

## Why the pipeline-conflict alert avoids saying "the panel above"

The conflict alert avoids saying "the panel above" because `PipelineProgress` can show a different, finished run when `surfaced_pipeline_run` prefers a pinned `?run_id=` over the in-flight run.

## Why the cable-downgrade banner needs its own isRunning gate

`downgraded` remains true after a run finishes because the subscription stays open as long as `remote_run_id` exists in `BillCreatorPipelineLlm.tsx`.

`isRunning` gates this banner separately from the poll itself (gated on `isRunInFlight`). Without this gate, the banner claimed a poll was running when none was active.

## Why the cable-downgrade banner overrides Alert's role to "status"

`Alert` defaults to `role="alert"`, but is overridden to `"status"` here because this is a reconnect notice rather than an assertive interruption.

No native tag replaces that behavior without dropping the design system component.

## Why ForceFailDialog requires typing the confirm phrase

`ForceFailDialog` serves as the confirmation modal for force-failing a pipeline run.

Typing "force fail" exactly is a deliberate friction step rather than the security check; `PipelineRunsController#force_fail` re-verifies both admin authorization and the confirm phrase on the server.

`BillCreatorPipelineControls` displays this dialog while a run has not finished. The copy follows the standard confirmation rules without variation.

## Why ForceFailDialog clears the typed phrase on any close path

Closing `ForceFailDialog` through Cancel, Escape, or the close icon resets the typed text so it opens empty on subsequent invocations.

## Why the force_fail POST sends back_to=bill_creator

Sending `back_to=bill_creator` selects the post-redirect route so a run without a bill lands on the all-bills pipeline tab while a single-bill run returns to the bill's pipeline page.

A run with no `bill_id` lands on `new_bill_creator_path(tab_key: :pipeline)`, whereas a run with a bill lands on `pipeline_bill_creator_path`.

## Why ForceFailDialog needs an explicit onError

Server refusals for a finished run or phrase mismatch arrive as `errors.pipeline` without flash messages, leaving the dialog open without feedback if `onError` is omitted.

`onSuccess` never runs on server refusals, so an explicit error handler is required to surface the rejection to the operator.

## Why PipelineStageSelector gets a whole-list setter, not per-toggle calls

`onSetStages` provides a whole-list setter so bulk selection actions never dispatch individual toggle calls.

Building Select all or Clear all from individual toggle calls arms multiple instances of the same delayed send timer, creating races that drop clicks during rapid interaction.

## BillCreatorPipelineControls test notes

Component tests verify preview debouncing when auto-included stages are selected and validate alert positioning relative to live subscription state.

Ticking a stage requests a fresh preview after a 300ms debounce interval so rapid clicks coalesce into a single request. The controls render beneath the pipeline-conflict alert, reading `subscriptionState` from `BillCreatorPipelineLlm`.

## usePipelineRunActions notes

`usePipelineRunActions` encapsulates action handlers for resuming, restarting, running, sweeping, and deleting pipeline runs.

The restart workflow operates as a single action, with the download-missing-assets toggle controlling asset re-fetching.

`handleResume` dispatches without a request body because the server determines the last failed stage and skips cached preceding stages.

`handleRestart` omits `download_missing_assets` so the controller inherits the setting from the parent run. Transmitting the active UI toggle state would override the parent run's configuration, whereas restart intends to replicate the original execution parameters.

`handleRun` handles server refusals through the shared notification channel, managing its posting state independently of `postOptions`.

`handleSweepStale` transitions non-terminal runs to failed status while preserving database rows for audit history.

`handleDeleteOrphans` removes abandoned rows outright, with the server re-validating candidacy before deletion to prevent stale count anomalies.

