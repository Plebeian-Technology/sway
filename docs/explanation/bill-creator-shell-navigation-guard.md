---
mode: explanation
summary: "Why BillCreatorShell guards bill/locale/tab/cancel-run navigation behind one unsaved-changes dialog, why IPendingNav's kind is explicit rather than inferred, and why each dialog sentence names only what that specific action actually loses."
status: agent-extracted
related: [docs/explanation/per-user-locale-props-never-once.md, docs/explanation/bill-creator-tab-url-routing.md, docs/explanation/carried-run-pin-single-param-design.md]
---
<!-- vale Vale.Spelling = NO -->

# BillCreatorShell navigation-guard mechanics

## Why the Summary tab is dirty-guarded and the Creator tab is not

The Summary tab is on this list because it is the SECOND EDITOR of
bills.summary — the Creator form writes that column, and so does Save
summary over there. Without the prompt, unsaved Creator-form edits could
be carried into a new Summary-tab save, silently overwriting the newer
text.

## Why IPendingNav's `kind` is explicit rather than inferred

A navigation the dirty guard is holding, and WHY the operator asked for
it.

`kind` is explicit rather than inferred from the destination href — a
shared href previously mixed up bill-switch and locale-switch dialog
copy.

Absent for "cancel-run": that action does not build its own address — the
server's redirect decides where the operator lands.

## Why pendingSwayLocaleId is separate shell state

The jurisdiction the operator picked but this screen has not yet
navigated away for — see AdminLocaleSelector's IProps (and
[per-user-locale-props-never-once.md](per-user-locale-props-never-once.md))
for why the picker needs this rather than the confirmed server locale
alone.

## Why changeTab builds the address the way it does

For a saved bill, the tab is part of the address:
/admin/bill_creator/:id/<tab>.

The new-bill flow has no bill id yet, so it visits the new-bill address
with a `?tab_key=` query instead, and the server reads it when rendering.
The Pipeline tab there means "run every bill", which is why the picker
relabels itself for it.

preserveScroll keeps the operator from being thrown to the top when
moving between tabs of different length.

Both branches build a fresh address, so the run the operator pinned has
to be carried across or it is lost on every tab change. See
[carried-run-pin-single-param-design.md](carried-run-pin-single-param-design.md)
for how `withCarriedRunPin` does that.

## Why onBillChange puts both the bill id and the tab in the address

Both the bill id and the tab live in the address:
/admin/bill_creator/:id/<tab>. No `?bill_id=` query needed — the address
is the one place that names the bill, and the server reads params[:id]
first.

The current tab is passed along so switching bills keeps the operator on
the same tab.

The sentinel needs the query form, because the new-bill address has no
tab segment. Without it, "All Bills" on the Pipeline tab means "run every
bill" but lands the operator on Bill Creator.

## Why onSwayLocaleChange always returns to the empty picker

Changing locale changes every available bill, so this always returns to
the empty picker at /admin/bill_creator/new rather than keeping an
address that points at a bill from another locale.

?sway_locale_id= is read by ApplicationController#find_current_sway_locale
and saved in a long-lived cookie, so later admin pages stay in the chosen
locale.

Goes through the same unsaved-changes prompt as switching bills, since it
leaves the bill the same way.

Set immediately, before deciding whether the nav can proceed. Without it
the picker is bound only to the confirmed server locale, and would snap
back to the old value until the visit lands.

## Why onCancelRun is the one place that sends the cancel-run DELETE

The one place that sends the cancel-run DELETE. Both Cancel buttons
(RunConflictBanner's and PipelineProgress's) decide only IF to cancel;
whether that's allowed right now goes through isCreatorDirty, same as
every other navigation on this screen.

The server redirects to wherever the run's bill lives — this screen does
not choose that destination.

PipelineProgress used to send its own DELETE, bypassing this dialog. Both
Cancel buttons take this callback as a required prop now, so a third one
can't skip it.

## Why confirmNav forwards pendingSwayLocaleId explicitly

The dialog's own state carries the picked jurisdiction — pendingNav has
no field for it — so a locale confirm must forward it here or the visit
silently reverts to whatever locale the server already has.

## Why cancelNav resets pendingSwayLocaleId

Staying means the locale switch did not happen, so the picker has to fall
back to the real, still-current locale rather than keep showing the one
that was clicked and then abandoned.

## Why the unsaved-changes dialog has one sentence per action kind

The copy below must name only what is actually lost — an unsaved
keystroke, and, on the locale/no-pending case, a summary edit — since
useTempStorage persists every other field.

Each of the three actions loses something different, so each gets its own
sentence below; a shared sentence previously described a locale change as
switching to "another bill".

The locale sentence deliberately avoids "so they are here when you come
back to it": there is one storage key (BillCreatorBillForm.tsx,
SWAY_STORAGE.Local.BillOfTheWeek.Bill), not one per bill, and the empty
picker this goes to has no bill loaded — the first field blurred there
overwrites this draft, same as opening a different bill.

## Why the confirm button is not `destructive`

Not `destructive`: for most of the form this action destroys nothing, and
a red button saying otherwise would be a false claim.
