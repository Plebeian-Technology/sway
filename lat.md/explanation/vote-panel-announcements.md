---
lat:
  mode: explanation
---
# What the vote panel announces

Casting a vote changes three things on the page. One announcer element carries the two that are ordinary progress, and the third — the offline warning — keeps a more urgent region of its own.

## What a screen reader hears when a vote is cast

[[app/frontend/components/bill/VotePanel.tsx#VotePanel]] renders a visually hidden `<output>` on every pass, holding the recorded-vote sentence, the saving sentence, or nothing. A screen reader hears which vote was recorded without going looking for it.

An `<output>` is a status region already, so the announcer needs no `aria-live` of its own, and the lint rule this repo runs prefers the tag over the role spelled out.

[[app/frontend/components/bill/voteAnnouncement.ts#voteAnnouncement]] picks which of the two sentences the announcer holds, so all three panels order them the same way: the saving sentence while a request is in flight, then the recorded sentence once it is not.

The ballot and corner-store panels are differently themed instances of the same control and carry the same announcer, so what is announced does not depend on the theme the reader chose.

The `aria-live` mark used to sit on the grid holding the two vote buttons. Everything worth announcing sits outside that grid, so a reader pressed a button and heard nothing about the result — and the mark made a live region out of two interactive controls, which is a noisy thing to watch for changes.

### Why the announcer is separate from the rows a reader can see

The confirmation row and the "Saving your vote" row carry no `aria-live` of their own. They appear and disappear with the vote's progress, and an element that is not in the page cannot be a live region that reports its own arrival.

The first attempt wrapped both rows in one live region collapsed by `empty:hidden` while empty. `empty:hidden` is `display: none`, which takes the element out of the accessibility tree, so the mutation that put text into the region also created the region — and screen readers commonly say nothing when content arrives together with the region holding it.

A separate `sr-only` announcer avoids that: `sr-only` clips the element to a single pixel and keeps it rendered, so the announcer is in the accessibility tree from the first paint and only its text ever changes. It also removes the layout question, because the visible rows are laid out exactly as they were before.

The offline warning is deliberately not part of it. That message says the vote did not leave the device, which the reader needs before anything else, so it carries `role="alert"` with `aria-live="assertive"` and interrupts.
