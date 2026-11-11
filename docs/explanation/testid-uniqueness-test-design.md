---
mode: explanation
summary: "Why testIdUniqueness.test.ts exists, how its two exception allowlists (MUTUALLY_EXCLUSIVE and SAME_FILE_BRANCHES) are argued and pinned, and how it extracts test ids out of source text."
status: agent-extracted
related: [docs/explanation/bill-as-introduced-title-split.md, docs/explanation/pipeline-busy-terminal-status-inversion.md]
---

# Why `testIdUniqueness.test.ts` exists and how its allowlists work

## Why the same `data-testid` on two components is a bug

Stops the same `data-testid` value from being used by two different
production components.

When two elements share a test id, `find("[data-testid='x']")` and
`getByTestId("x")` return whichever element the page happens to hand back
first, so a test can check the wrong one and still pass. That is how one real
bug surfaced: `btn-paste-summary` sat on two components, and a browser test
was driving the wrong button.

Some repeats are correct. The themed layouts are built so that only one of
them is ever on screen. Those are listed in `MUTUALLY_EXCLUSIVE` below, each
with the piece of code that guarantees only one shows up.

## Why `MUTUALLY_EXCLUSIVE` names the guaranteeing function

Test ids that turn up in more than one component for a good reason: those
components can never be on screen together. Each entry names the function
that picks exactly one of them. If that function goes away, the exception has
to be argued again rather than quietly living on.

## The `BillHeader` entry

Same function, and each of those layouts carries one heading for the bill.
The id exists so one test can ask every theme the same question: does your
heading show the bill's subject rather than the legislature's own wording? `BillHeader` is the heading for the sway and classic themes,
which both resolve to `DefaultBillLayout`. See
`docs/explanation/bill-as-introduced-title-split.md` for the wording bug
behind that question.

## Why `SAME_FILE_BRANCHES` exists, one level in from `MUTUALLY_EXCLUSIVE`

Each test id here maps to the ONE file allowed to write it in more than one
place in the JSX, plus the exact number of places. Those places are
alternative returns: one of them runs and the rest do not, so only one
element with that id is ever on the page.

Same bargain as `MUTUALLY_EXCLUSIVE`, one level in. Reading the source text
cannot tell alternative branches apart from two elements side by side in one
tree, so each case is argued once and written down here.

The COUNT is part of the record on purpose. Letting a file off the hook for a
value outright would mean an eleventh spot added to a ten-branch component —
a sibling this time, not another branch — inheriting an exception nobody
argued for. Pinning the number makes any new spot fail until someone looks.

## The status-pill entry's count

Status pills: one `if` per status, each returning its own `<Badge>`. Two of
these come from `const testId = scope === "bill" ? ... : ...`, which is
why the scanner had to learn to follow a variable back to its value.
7 rather than 6 since the badge gained an arm for a run nobody is working
on any more. It used to stamp "Queued…" over a notice saying the run had
stopped. See
`docs/explanation/pipeline-busy-terminal-status-inversion.md` for the
related pipeline-status-shape decisions in this component family.

## Why it looks past the `data-testid` attribute name

The attribute names that set a test id. `data-testid` is the real HTML
attribute; `testId` and `dataTestid` are prop names that local wrappers use to
pass one along (the detail-row component in `pages/Legislator.tsx`, and
`components/ui/combobox.tsx`). Looking at `data-testid` alone meant the five ids
`Legislator.tsx` sets with `testId="..."` appeared in NO list at all.

## How it extracts test id values from source text

Pulls every written-out test id value from one source file. It handles the
shapes this codebase uses: a plain string; a `{...}` expression holding
strings, such as a ternary; a template string, where every `${...}` is
rewritten to `${}` so `x-${org.id}` and `x-${organization.id}` count as the
same id shape; and a bare variable name, which is looked up against a `const`
in the same file.

That last case closed a real blind spot. `BillCreatorPipelineStatusBadge`
assigns `data-testid={testId}` at nine JSX sites from
`const testId = scope === "bill" ? "bill-pipeline-status-badge" : "pipeline-status-badge"`,
so neither of the ids it owns was visible here. A variable with no matching
`const` in the file is genuinely passing along somebody else's id (a
`dataTestid` prop, `props["data-testid"]`) and is still skipped.

## Why occurrences are counted per file, not just tracked as "more than one file"

Test id -> file -> how many places in that file set it. Counting is what
makes a repeat WITHIN one file visible. The old version only kept a set of
files and asked whether there was more than one, so it could see clashes
between files and nothing else. Yet a component that renders the same id
twice in one tree confuses `getByTestId` in exactly the same way.

## Why both allowlists needed the same safe-lookup fix

Both allowlists are plain objects looked up by a test id read out of the
source, so both can be asked about a name every JavaScript object already
answers to. Only `MUTUALLY_EXCLUSIVE` was pinned. `SAME_FILE_BRANCHES` was
written with the safe lookup and had nothing holding it there, so an edit
back to `value in map` would have gone through green — the same hazard,
guarded on one map and not its twin.

## Why the within-one-component check has its own explanation of the branch rule

A component may set the same id in more than one place ONLY when those
places are alternative returns: one runs, the rest do not. Reading the
source text cannot tell that apart from two elements side by side in one
tree, so each case is written down here with its reason, exactly the way
the cross-file list above works.

## Why the unsafe-lookup guard reads the file's own text

The examples above describe the two lookup forms; they cannot see which
form this file actually uses, so on their own they would stay green
through the edit they exist to prevent. This reads the file and fails on
the unsafe form written directly against either map. Comment lines are
dropped first, because prose mentions both names in passing. Proven
failable by putting the banned form back.
