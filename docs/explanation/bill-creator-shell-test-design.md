---
mode: explanation
summary: "Why BillCreatorShell.test.tsx fakes the confirm-dialog provider and several Radix widgets instead of mounting the real ones, and the copy bugs its dialog-copy examples caught in the jurisdiction-switch and empty-picker dialogs."
status: agent-extracted
related: [docs/explanation/org-position-bill-testimony-check.md]
---

# Why BillCreatorShell.test.tsx fakes what it fakes

## Faking the confirm-dialog provider

`BillCreatorLlmSummary` asks "are you sure?" before Clear, because clearing
blocks approval of every draft position that came from the testimony. This
shell renders that component, and in production the confirm dialog's provider
sits at the top of the app (App.tsx), so the test fakes it instead of mounting
the real one.

## A stale prop on the pipeline stand-in

`BillCreatorPipelineLlm` takes one prop: the shell's cancel-run handler, which
it hands down to PipelineProgress's Cancel button so that button cannot leave
the screen without asking about unsaved changes. This stand-in used to accept
a `billPickerSlot` prop that no caller has passed since the bill picker moved
up to the shell — the double was describing a contract that no longer exists.

## Stand-ins for the Radix UI widgets

Stand-ins for the Radix UI widgets. Combobox, Select, Tabs, and Dialog all
rely on portals and pointer capture, which jsdom (the fake browser these
tests run in) does not implement. These replacements are plain HTML, so the
tests can check navigation and dialog behavior without touching Radix
internals.

The bill picker renders the shared combobox component, so the
`bill-select*` test ids that the navigation and "New Bill" checks rely on are
defined here. The plain Select stand-in below is still needed by the Summary
subtree, which is not mocked and uses the shared select component
(BillCreatorOrgPositionCardEditor).

## The jurisdiction-switch dialog used to speak in bill wording

Changing jurisdiction shared `pendingBillHref` with the bill
picker, and every part of the dialog branched on that one value. So an
admin who picked Baltimore City or US Congress was shown the copy written
for switching BILLS — "Working on another bill replaces this draft" —
under a button reading "Switch bill". Nothing on screen named the
jurisdiction they had chosen, so the safe reading was that they had
mis-clicked the bill picker, and pressing Stay cost them the switch they
meant to make. The shared copy was generic before it was sharpened, so
making the bill wording right is what made this wording wrong.

## Only the tab container is tested here

The four panels aren't what this file is about — each reaches for page props, Inertia forms, ActionCable.
Only the tab container is tested here.

## The unsaved-changes prompt must guard the tab that CAN write bills.summary

bills.summary is written by both the Creator tab's form and the Summary tab's Save — the unsaved-changes
prompt used to guard the tabs that CAN'T write it and skip the one that can.

## A pinned run must survive a tab change

The suites above run at an address with no run_id, so deleting withCarriedRunPin left every example green
without exercising it. This pins a tab change carrying ?run_id= forward.

## The empty-picker dialog's retention promise was false

There is one draft storage key, not one per bill
(BillCreatorBillForm.tsx, SWAY_STORAGE.Local.BillOfTheWeek.Bill), so
the empty picker this dialog sends you to overwrites this draft the
moment a field there is blurred — the same way opening a different
bill does. The old copy promised the draft would be "here when you
come back to it", which is the retention the sibling bill-switch
sentence explicitly says does NOT happen.
