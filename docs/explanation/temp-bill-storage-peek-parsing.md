---
mode: explanation
summary: "Explains why TempBillStorage#peek returns unknown, why it no longer announces a load with a toast, and why a bad parse returns null instead of throwing."
status: agent-extracted
related: []
---
<!-- vale Vale.Spelling = NO -->

# Why `TempBillStorage#peek` is shaped the way it is

`TempBillStorage#peek` parses a Bill Creator draft out of `localStorage`. It
has no side effects, and it types its return as `unknown` rather than
whatever `JSON.parse` hands back: nothing in this class knows what was
stored, and a type that claims otherwise would make every reader's mistakes
invisible. The caller narrows the result — see `asStoredBillDraft`.

## Reading no longer announces itself

There used to be a `get()` next to `peek()` that popped a "Loaded Data from
Temp Storage" toast on a timer. Its one caller restored the draft while the
form was being built, so the toast had to be scheduled out of the render —
and because the read and the announcement were the same call, the
announcement fired again on every later read. Reading is now separate from
saying so, and the one restore that needs to announce itself does so once
.

## A bad parse returns `null`, on purpose

The parse is TOTAL — it never throws — which is what returning `unknown`
implies anyway. The parse used to be unguarded, and its caller is now a lazy
`useState` initializer, so it runs DURING RENDER: any malformed entry under
the key threw a `SyntaxError` through `PageErrorBoundary`. The one control
that clears the draft, "Don't Save + Reset to New," lives inside the
subtree that had just fallen over, so the operator's only route back was
browser devtools. `asStoredBillDraft` already rejects anything that isn't a
plain object, so answering `null` on a bad parse costs one unrecoverable
draft instead of the whole screen.

This round narrowed the guard from `stored ? … : null` to
`stored === null ? … : …`, which sent the empty string to `JSON.parse` as
well — the guard has to be narrowed exactly that way, not merely "truthy",
for the total-parse promise above to hold. `useNewBillInitialValues.test.ts`
pins this.

## The restore runs once, in `useNewBillInitialValues`

`useNewBillInitialValues`'s one-time draft restore reads `peek()` and
decides what to show, once per mount. THE RESTORE RUNS ONCE, because it
happens once. This whole block used to sit in a `useMemo` keyed on
`[bill, …]`, and `bill` is `props.bill` — a fresh object on every Inertia
props swap, of which this screen has many: `RunConflictBanner`'s Cancel,
every five-second poll, every Save Bill.

Recomputing it changed nothing the form could see. `useForm` reads its
argument at mount and never again, so a new object re-seeded nothing. What
it did do was repeat the block's side effects: the restore toast fired on
every refresh, and so did the "your unsaved summary was not restored" one —
which then stated two things that were false on that render, because
nothing had been restored and the box held whatever
`BillCreatorBillForm`'s guarded follow decided, not the server's text.

A lazy `useState` initializer is the run-once primitive here. It is a pure
read: `peek()` parses and returns, and nothing is announced from it.
Switching bills rebuilds this hook anyway — `BillCreatorBillForm` is keyed
on `bill.id` — so once per mount is once per bill.

SAYING SO IS A SIDE EFFECT, so it lives in an effect. Both messages
describe the restore, the restore happened once, and an effect with an
empty dependency list is the one place that can be said once. It also
removes the reason the old code needed timers: a toast raised from an
effect is raised after the commit, not in the middle of a render.

Dropping the operator's unsaved summary is a loss, and it used to happen
under the same generic restore toast as an ordinary one — so the paragraph
they wrote vanished with nothing said. That is why it is a second, separate
error-level toast rather than folded into the "Loaded Data from Temp
Storage" one.

`useNewBillInitialValues.test.ts` pins this as "says each thing once, even
when the page props refresh under the form": both used to live inside a
`useMemo` keyed on `[bill, …]`, and a recomputation re-seeded nothing but
re-fired both toasts. The second one then stated two things that were
false on that render: nothing had been restored, and "the saved summary is
in the box" is whatever `BillCreatorBillForm`'s guarded follow decided —
for a half-typed edit, the operator's own text. The toast steered them
wrong on the one path this thread of work exists to close.

## Why TStoredBillDraft is a Partial

What the Bill form writes to browser storage: the form's own values, plus
the published summary the draft's text was written against.

PARTIAL is deliberate — older drafts carry fewer keys than today's form.
Declaring this complete let a missing key reach the form as `undefined`
while the type promised a value.

## Why asStoredBillDraft is a shape check, not a schema check

The one seam between "some JSON came out of localStorage" and "this is a
bill draft".

peek() answers `unknown`, not JSON.parse's type — that type let a draft
flow unchecked into the form's initial values, hiding shape changes from
the compiler.

A SHAPE check, not a schema check — deliberately. This app is the only
writer of the key, so the real question is whether the value survived as
an object at all.

Field-by-field validation would be a second declaration of the form's
shape — one more place to keep in step.

## Why the file stays at this path for now

`TempBillStorage.ts` sits at this path because the since-deleted V1 tree
imported it from here. It can now move into
`components/admin/creator/utils/`; that move has not been made yet.
