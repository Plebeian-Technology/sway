---
lat:
  mode: explanation
---

# Why the Summary tab polls while a pipeline run is in progress

`BillCreatorSummaryAndPositions` mounts `SummaryGenerationPoller` under three conditions: `isGenerating`, `hasNoProvisioning`, and `isBillPipelineRunning`.

The third exists to cover a gap the ActionCable subscription alone cannot close.

## The gap: a missed message never arrives again

Without the third condition, a finished summary is neither "generating" nor "missing" once its pipeline run completes, so nothing polls — the tab bets on exactly one ActionCable message arriving to tell it the run finished.

`usePipelineRunSubscription`'s catch-up reload only fires after a disconnection long enough to raise the "paused" banner. Swapping tabs on the Bill Creator screen is not that kind of disconnection, so a message missed during a tab change never gets a catch-up reload to fall back on. The result was a stale "generation unavailable" notice sitting over a run that had already finished, with no way out but a manual page reload — not an acceptable outcome in any workflow on this screen.

This is reproduced in `spec/system/admin_pipeline_run_finish_spec.rb`, which finishes the run without sending the ActionCable message.

## Why the spec examples move the run's status directly, not through a real finish

`spec/system/admin_pipeline_run_finish_spec.rb`'s examples are deliberately not written as "watch the screen and see." While a run is going.

`spec/system/admin_pipeline_run_finish_spec.rb`'s examples are deliberately not written as "watch the screen and see." While a run is going, the Summary tab greys out every button that spends money on the language model and draws one notice saying why; when the run finishes, that notice has to go on its own — reloading the page is not allowed to be part of any workflow here, because a person cannot be expected to remember to do it. Each example moves the run to its finished status from the server side and then waits for the notice to disappear, so it can fail with nobody looking at anything (found by hands-on testing).

The first example (`run.mark_succeeded!`) is the ordinary ending: the run finishes and the message announcing it arrives through the real state-machine event's `after_commit` hook — the same one the orchestrator fires. It stays covered so a change that repaired the missed-message path by breaking the working one would be caught.

The second example is the one that matters, and covers the real bug: `run.update_columns(status: "succeeded", completed_at: Time.current)` writes the finished status without running the callback that sends the ActionCable message. A development log showed the tab subscribing and unsubscribing in the same thousandth of a second, then silence over the run finishing. Chasing that exact timing in a spec would give a test that fails about two runs in three, which is no gate at all — so the message is removed instead of raced. Nothing about the resulting state is faked: a message that is never sent and a message that is sent to nobody leave the screen in the same position. What is left to prove the notice clears is the five-second poll timer, which is on only because a run is going — take that reason away and this example fails, because there is no second chance anywhere else in the UI to catch the missed message.

The third example follows the route an operator actually took: the run was started on the Pipeline tab and they moved to the Summary tab. A tab change on the Bill Creator screen is a client-side visit, so the browser keeps one WebSocket connection open and swaps which parts of the screen listen on it — the moment a live message is most likely to fall through, and the scenario this whole poll fallback exists for.

## Why the timer's lifetime matches the notice's

`isBillPipelineRunning` reads the same value (`bill?.bill_pipeline_refresh?.status`) that the "generation unavailable" notice itself reads.

That keeps the poller mounted for exactly as long as there is a notice on screen to take down, and lets it unmount itself the moment the notice would stop showing — no separate start/stop bookkeeping needed.

## BillCreatorSummaryAndPositions.test.tsx pins the completed+running pairing

A finished summary is neither generating nor missing, so nothing puts the poller up — a dropped live message used to leave the "unavailable" notice stuck.

The status here is `completed` on purpose: it is the exact pairing that used to fall through, and it is what the operator had on screen.
