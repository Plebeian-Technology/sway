---
lat:
  mode: explanation
---

# PipelineTerminalAlerts: the failed-run remedy wording

The history behind PipelineTerminalAlerts' failed-run remedy wording and why the succeeded-stage chip says only that the stage succeeded on this run, not that it is cached.

## Why PipelineErrorsAccordion's errors prop is NonNullable

`NonNullable` because the run's own `errors` is optional — the server does not send it until the channel does.

This component needs a real list, and its caller supplies one by defaulting the absent case to `[]`. Keeping the requirement here means the caller cannot quietly drop that default.

## Why the failed alert no longer says "check the Solid Queue job logs"

IT SAID "check the Solid Queue job logs".

No jobs dashboard is mounted — `config/routes.rb` has no `mission_control` — so that meant an SSH session on the Pi. `BillCreatorPipelineControls` draws Resume and Restart directly above this alert on the same screen, so the remedy names those instead. Second site of the shape already found on the summary branch, found by that finding's sweep.

`PipelineTerminalAlerts.test.tsx`'s "renders the failed alert with the error message and a phase label" is A GUARD: it passes against the wording as it stands. That was corrected with nothing pinning it, so restoring it left every gate green. The sibling summary branch already asserts this.

## Why the remedy names Resume/Restart only on a failed single-bill run

AND THEN NAMED THEM ON RUNS THAT HAVE NEITHER.

This alert draws on the status alone, while `BillCreatorPipelineControls` mounts `PipelineResumeActions` behind `failed && kind === "single"` — so a failed all-bills run, or a partial payload with a null kind, was sent to look above for two buttons that are not there. Same harm as the wording it replaced. The other arm names what those runs really have: the stage picker and the Run pipeline button, both of which `BillCreatorPipelineControls` renders for every run above this panel, and `failed` is terminal so the button is not disabled. It is the same instruction `PipelineProgress` gives on an empty panel. The test is the same one the chips already use.

THE REMEDY HAS TO NAME CONTROLS THAT ARE ON THE PAGE. Resume and Restart are drawn by `PipelineResumeActions`, which `BillCreatorPipelineControls` mounts behind `run.status === "failed" && run.kind === "single"`. This alert draws on the status alone, so a failed all-bills run — the state the run summary card exists for, and the state the second example renders — was sent to look above for two buttons that are not there. Same harm as the "check the Solid Queue job logs" wording this copy replaced: a remedy that cannot be followed.

The stage picker and the Run pipeline button are the controls an all-bills run really has: `BillCreatorPipelineControls` renders `PipelineStageSelector` and `PipelineActionButtons` for every run, above `PipelineProgress`, and `failed` is terminal so the button is not disabled by `isInFlightRunStatus`.

## Why the remedy no longer says the button retries the whole run

AND THEN SAID THAT BUTTON WOULD RETRY THIS RUN.

It cannot. `handleRun` posts `bill_id: pickedBillId` (`usePipelineRunActions`), so with a bill loaded in the shared picker it starts a run for that one bill — the button even says so, "Run pipeline for bill X". The run drawn here is not scoped to the loaded bill: `LegislationPipelineRunSourcing` takes `?run_id=`, else the newest run still in flight, else the newest run of any status, with no `bill_id` filter. So a failed all-bills run and a loaded bill sit together on the ordinary `/bills/:id/edit` screen, and "to try it again" sent an operator to click a button that runs one bill of the two hundred that failed.

So the alert states what the button covers and stops there. It does not tell them to switch the picker to All Bills either: `BillCreatorShell`'s `onBillChange` visits `ROUTES.billCreator` for that entry, which is `/admin/bill_creator/new` with no tab and no query, so it drops both the `?run_id=` that put this run on screen and the stage selection `usePipelineControlsState` keeps in the URL. Naming that as the next step would be the fourth remedy in a row that cannot be followed.

THE BUTTON RUNS ONE BILL WHENEVER THE PICKER HOLDS ONE. `handleRun` posts `bill_id: pickedBillId`, and the run drawn here is chosen without any `bill_id` filter, so a failed all-bills run and a loaded bill is the ordinary state of `/bills/:id/edit`. The wording this replaced said "click Run pipeline to try it again", which promised a retry of the all-bills work from a button whose own label reads "Run pipeline for bill X". `PipelineTerminalAlerts.test.tsx` pins both halves of the fact the component is now given.

## Why the "succeeded" stage chip does not say "cached"

On a failed single-bill run, every earlier stage that succeeded gets a "succeeded" tag.

This is NOT the same claim as "cached": that is the server's call at Resume time, based on whether the artifact is still on disk, and this row only knows the stage succeeded on this run.

"Cached" and "will be skipped on Resume" are the server's call, not something the browser can see: it decides at Resume time which stages still have their artifact on disk. This row only knows the stage succeeded on THIS run, so it says only that.
