---
mode: explanation
summary: "Why BillCreatorBillForm tracks published-summary provenance separately from the resync guard, reports dirty state directly instead of through an effect, resets once per bill, dedupes its save toast via the flash, and gives dropdown fields onStored instead of onBlur."
status: agent-extracted
related: [docs/explanation/editable-summary-field-server-resync-guard.md, docs/explanation/select-field-autosave-draft-timing-bug.md]
---
<!-- vale Vale.Spelling = NO -->

# BillCreatorBillForm mechanics

## Why BillCreatorBillForm owns the useForm() instance

Bill creator details form. Owns the Inertia useForm() instance and shares
it through SwayFormContext so the organizations and votes sections render
inside the same form.

## Why publishedSummary reads straight off page props

The SERVER's published summary, read straight off the page props rather
than off initialValues — initialValues may itself be a restored draft, and
a draft cannot be its own provenance.

Seeds the ref with the form's initial value. SummaryField keeps it current
via onChange as the field is edited from form.data.summary, the source of
truth.

## Why the stamp records what the box was written against, not the current published summary

The stamp must record what the box's text was WRITTEN AGAINST, not "the
published summary right now" — those differ whenever another save lands
mid-edit.

toStore used to read the live value at blur time, so a props refresh
mid-edit stamped the NEW summary onto OLD text — the draft matched and
republished stale text over the newer save.

Box and server agree here — either the resync-guard follow ran (see
`docs/explanation/editable-summary-field-server-resync-guard.md`), or this
is the form's own save landing. Either way the text was written against
what the server now holds, so provenance moves with it.

When they disagree, the box holds an unsaved edit and the value it was
written against hasn't changed.

## Why dirty state is reported directly, not through an effect

Tells the parent about unsaved changes right where they happen — markClean
on save, onFormChange on typing — not a local "dirty" flag copied up
through an effect.

## Why the mount effect resets dirty state exactly once

Runs once at mount only, to seed state the parent owns — not the banned
reset-on-every-prop-change relay pattern.

React rebuilds this component per bill (keyed on bill.id), so without this
reset the parent's "unsaved changes" flag would carry over from the
previous bill.

## Why there is no `?saved=` query check for the create/update toast

"Bill Created"/"Bill Updated" arrive as a Rails flash message (via
inertia_share); registerFlashToasts shows each one once, in one place.

No ?saved= query check here anymore — it showed the same message twice
when two creator sections were on screen at once.

## Why the dropdown fields take onStored, not onBlur

The dropdowns take `onStored`, not `onBlur` — their trigger blurs when
Radix opens the listbox, so an onBlur here would save the value the
operator was about to replace.

## Why SummaryField writes straight to form.data, not a local copy

The value lives in exactly one place. The textarea and the preview both
read `form.data.summary` directly, not a copy held in local state, so a
write from elsewhere — an LLM pasting a summary back, or `form.reset` —
shows up at once. The old local copy ignored incoming changes and kept
showing old text until the component was rebuilt. `onChange` writes to
`form.data`, which is the real store, AND keeps the forwarded ref current
for the submit and autosave code that reads it. No effect involved.
