---
mode: explanation
summary: "Why useNewBillInitialValues types its useMemo callback the way it does, why bill is optional on the page props, why status is narrowed rather than trimmed, and how draft-restore scopes a stored draft to the bill it belongs to."
status: agent-extracted
related: [docs/explanation/temp-bill-storage-peek-parsing.md, docs/reference/bill-creator-form-type-contract.md]
---
<!-- vale Vale.Spelling = NO -->

# `useNewBillInitialValues`: building and restoring the form's initial values

See
[temp-bill-storage-peek-parsing.md](temp-bill-storage-peek-parsing.md) for
the run-once restore effect and the `TempBillStorage#peek` parsing
contract this hook builds on.

## Why `bill` is optional on the page props

OPTIONAL, matching `BillCreatorShell` and `BillCreatorAccordions`, which
render the same page and have always said so. Both controller actions
behind this page do send it — `#new` sends `Bill.new.attributes` and
`#edit` redirects when `@bill` is blank — but that is a guarantee made by
two controller lines, not by this type, and this file used to argue both
sides of the question inside one object literal: `bill.id` unguarded on
one line, `bill?.title` on the next.

## Why the return type annotation goes on the callback, not on useMemo's argument

THE ANNOTATION GOES ON THE CALLBACK, and the position is the whole point.
The hook's own return annotation accepts an object carrying keys the type
does not declare, which is how `summary_preview` lived in these initial
values — read by nothing, but seeded into `useForm`'s data and spread into
the body of every Save Bill.

`useMemo<IApiBillCreator>(...)` does NOT close that. Measured: with the
type named as `useMemo`'s argument the compiler accepts an invented key,
and with it named as the callback's return type the same key is a compile
error. Only the second form makes the literal fresh, so only the second one
checks both directions — no missing field, and no invented one.

## Why `status` is narrowed rather than trimmed

Narrowed rather than trimmed-and-hoped. `.trim()` widens the server's value
back to `string`, and the `any` further down this file used to absorb
that, so an unrecognised status reached the dropdown as a value with no
matching option — which draws as an empty control, not as an error.

## `billStatus.ts`: EVERY_BILL_STATUS and asBillStatus

Every bill status, written once so the compiler checks this list against
the type.

`satisfies Record<sway.TBillStatus, …>` fails to compile if the union
gains a status this object doesn't have — the only way to keep a
hand-written member list honest.

`asBillStatus` narrows a bill status that arrived as text. The server
sends `status` as a string, and trimming it widens the type back to
`string` — whatever it started as.

That widening used to be absorbed by an `any` further down the same
object literal, so the Bill form's initial values carried an unchecked
string under a type promising one of four words.

An old value, a typo in a fixture, or a renamed column would reach the
dropdown as a value with no matching option — which draws as an empty
control, not an error.

Returns undefined for anything that is not one of the four, so the caller
chooses the fallback rather than inheriting one.

## Why the stored draft is scoped to the bill it was taken against

The draft is stored under one global key, not one key per bill, so a saved
draft may only come back for the bill it actually belongs to. Without this
check, a draft from one bill overwrites the fields for every other bill
picked in the selector, and switching bills looks like it did nothing at
all.

`useNewBillInitialValues.test.ts` pins this: picking a different bill in
the creator has to change the form fields. The hook now brings a draft
back only when it belongs to the bill currently loaded.

## Why a restored draft goes OVER the server-derived values, not the reverse

The draft goes OVER the server-derived values rather than replacing them. A
draft is partial by nature — it holds what the form held when focus last
left a field, and one written by an earlier build knows nothing of fields
added since — so anything it does not carry falls back to the bill,
instead of reaching the form as a missing key.

## Why the draft's summary yields to a newer published one

The Summary tab edits `bills.summary` too. A draft written before a save
made there used to come back holding the older text, and the next Save
Bill published it over the newer one — with nothing on screen saying so.
`reconciledDraftSummary` hands the draft's own summary back only while the
server's value is still the one the draft was taken against.

THE ONE THIS EXISTS FOR: the operator edits the summary on the Creator tab
and does not save; the draft goes to storage. They move to the Summary tab
and save a different summary there. Coming back, the draft used to
reinstate the older text, and the next Save Bill published it over the
newer one. `useNewBillInitialValues.test.ts`'s "drops the draft's summary
once the server's has moved on" pins this.

## `billDraftSummaryProvenance.ts` internals

### Why `summary_at_draft_time` is captured, not read live

The published bills.summary the draft's text was WRITTEN AGAINST — not
whatever the server held at store time.

The two differ whenever props refresh between typing and blurring;
stamping the wrong one would forge a current stamp onto superseded text.

`summaryWrittenAgainst` (the value stamped in) comes from the SERVER's
props, never the form's own value, since a restored draft can't be its own
provenance. Captured when the text was authored, not read live at store
time: reading it live would let a props refresh in between stamp a
superseded draft as current.

### Why `summary_at_draft_time` is cleared on the reconciled values

Cleared: the stamp is a storage detail and has no business in the form.

### Why `yielded` exists on IReconciledDraftSummary

True when the draft's own summary was thrown away and the server's put in
its place — an unsaved edit being lost.

The caller must say so: the only prior signal was the generic "Loaded Data
from Temp Storage" toast, which this module already treats as insufficient
for the opposite loss.

### Why yielded only reports when something was actually lost

Yielding is only worth reporting when something was actually lost: a draft
holding the published text word for word has nothing to report.

That is the common case, where the operator edited other fields and never
touched the summary — a toast there would teach them to ignore the one
that matters.
