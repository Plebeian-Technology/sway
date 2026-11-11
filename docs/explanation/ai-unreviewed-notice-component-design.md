---
mode: explanation
summary: "Why AiUnreviewedNotice is one shared component with no hardcoded count of call sites, and why the notice is never baked into the text it annotates."
status: agent-extracted
related: [docs/explanation/bill-summary-ai-unreviewed-detection.md]
---
<!-- vale Vale.Spelling = NO -->

# Why `AiUnreviewedNotice` is a single shared component

`AiUnreviewedNotice` renders, under a piece of text, that a machine wrote it
and no person has revised it. See
[Detecting an unreviewed AI summary](bill-summary-ai-unreviewed-detection.md)
for how the server decides the flag it reads.

## One component for every such piece of text

Two kinds of text carry this notice: the bill summary, and each
organization's reason for its position. Several components render each
kind, one per bill layout. Typing the sentence out at every call site would
get it reworded at all but one of them over time. No count of call sites is
kept in this component on purpose — a number in a comment goes stale the
moment a new bill layout is added.

## The notice is never part of the text

The server sends a flag beside the text, and this component renders the
sentence from that flag. A person who revises the text removes the notice
automatically, with no string to strip by hand. Every other reader of the
text — the mobile app, the JSON API — decides for itself how to show the
same flag, rather than inheriting a hardcoded sentence baked into the text
itself.

It renders nothing when the flag is false, so a caller can pass the flag
straight through with no condition of its own.

## Why `BillSummaryMarkdown.tsx` attaches the notice, not each bill layout

`aiUnreviewed` is true when the summary is a machine's words that no person
revised — the notice then goes under it.

The notice is attached in `BillSummaryMarkdown.tsx`, and not in the bill
layouts. Every layout renders the summary through this component; adding the
sentence to each layout instead would mean all but one of them get it.

The prop is optional so the admin previews that use this component show the
plain text they preview.

## Why `OrgPositionSummary.tsx` is a component for one paragraph

One organization's reason for its position on a bill. The notice goes under
it when a machine wrote the reason and no person revised it.

Several screens render this text, and each styles it differently: the bill
layouts, the organization page, and the organization's own position card.
Adding the notice at every site by hand would mean all but one end up with
it. The `className` stays with the caller, so each layout keeps its own
look. The notice does not. To find every caller, grep for
`OrgPositionSummary`.

Its `prefix` prop — the words a layout puts in front of the summary inside
the same paragraph ("In support. ", "In opposition. ") — exists as a prop,
and not as a reason to let those layouts write their own paragraph instead
of using this component: a component that all but two callers go through is
how those two get missed.

## What the test file's examples are pinning down

The notice under text a machine wrote that nobody has revised.

The rule these examples hold down is that the notice follows the SERVER's
answer for each piece of text, and is never part of the text itself. A test
that only rendered it with the flag on would pass whether or not the flag
was read at all, so every case below is paired with its opposite.

## Why the notice's sentence lives in `PARITY_COPY`, not a component prop

`PARITY_COPY.bill.content.aiUnreviewedNotice` is shown under any text a
machine wrote that no person revised: the bill summary, and each
organization's reason for its position.

The server sends a flag for each piece of text. This sentence is never
stored in the text. So a person who revises the text removes the notice,
and nothing has to strip a string.

It lives here because web and mobile both load this file. One app showing
the notice and the other not is worse than neither.
