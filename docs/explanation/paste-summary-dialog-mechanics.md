---
mode: explanation
summary: "Why PasteSummaryDialog reads rejections from flash rather than Inertia's shared errors, why NO_ERRORS is one shared array, how error-click scrolling resolves a JSON Pointer, and why its onSuccess handler reads the fresh page.props instead of the pre-request usePage() snapshot."
status: agent-extracted
related: [docs/explanation/dismissed-paste-summary-errors-tracking.md, docs/explanation/paste-summary-dialog-draft-landing.md, docs/explanation/paste-summary-dialog-dismissal-persistence.md, docs/explanation/bill-creator-landed-write-detection.md]
---
<!-- vale Vale.Spelling = NO -->

# PasteSummaryDialog mechanics

## Why rejections come back via flash, not Inertia's shared errors

Pastes bill summary JSON matching config/schemas/bill_summary.json; the
server validates it and saves to bill_llm_provisioning.

Rejections come back in flash[:paste_summary_errors], not Inertia's
shared `errors` — the value every other form on this page uses.

## Why schemaExample is a plain string prop

A string, not an object, so the parent controls exactly what's shown.

Currently hardcoded by the parent; could later be read from
config/schemas/bill_summary.json without changing this component.

## Why NO_ERRORS is one shared empty array

One shared empty array so "no errors" is always the same object — the
list never redraws for nothing, and the dismissed-check below can't match
a fresh empty array by accident.

## Why the flash read has no manual-clear cleanup

Flash clears itself on Inertia's next page visit, so nothing here clears
it manually.

An earlier version wired up `errorBag`/`onError` for this too; both were
dead code since the server never targets them, and are gone now.

## Why dismissedErrors starts from the module-level registry, not null

Tracks which flash-error batch the operator already saw. The poller never
re-requests the flash, so without this, reopening after closing would
show stale errors beside an empty box.

Starts from a module-level registry, not `null`. This dialog mounts from
two mutually exclusive branches, and the same 5s poll can flip which one
is active mid-view. See
[dismissed-paste-summary-errors-tracking.md](dismissed-paste-summary-errors-tracking.md)
and
[paste-summary-dialog-dismissal-persistence.md](paste-summary-dialog-dismissal-persistence.md)
for why the registry itself is a module-scoped WeakSet.

Render reads the state, not the registry — it's consulted only at mount,
since a dismissed array could only reappear as `flashErrors` if it's the
one just read here.

## Why handleErrorClick falls back to scrolling to the top

Each error names a JSON Pointer path (e.g. "/sections/0/title"). When the
path can't be resolved — invalid JSON, or the path isn't in the document
— falls back to scrolling the box to the top.

setSelectionRange throws if the box has been taken off the page
mid-render. The focus() above is enough on its own.

## Why handleValidate's onSuccess reads the fresh page.props, not the earlier usePage() snapshot

No `errorBag`/`onError` here on purpose — rejections arrive via
flash[:paste_summary_errors], which `errors` above already reads. Adding
these back would revive dead code.

Inertia calls `onSuccess` even on a rejected paste — a redirect carrying a
flash message still counts as success to it. See
[paste-summary-dialog-draft-landing.md](paste-summary-dialog-draft-landing.md)
for the browser-spec history behind this.

So this must check the new page's flash to tell a real save from a
rejection, or the dialog would close with errors never shown.

Reads flash off `page.props` (the response just received), not the
`usePage()` snapshot above (from before the request).

Rejected — leave the dialog and text as-is so the operator can fix the
JSON; `errors` above picks up the new flash on next render.

A lapsed admin session redirects to `/` (verify_is_sway_admin) with no
paste_summary_errors, so this read as a successful save though nothing
was written. See
[bill-creator-landed-write-detection.md](bill-creator-landed-write-detection.md)
for the general pattern this check follows.

## Why there is no router.reload after a successful paste

No router.reload here, same as the organization position card:
#paste_summary redirects to summary_bill_creator_path, and Inertia
already followed that redirect with a GET before this runs.

Proof: this handler already reads the FRESH `page.props` above — the
saved data is already in the browser, so reloading would just re-ask for
what we just received.
