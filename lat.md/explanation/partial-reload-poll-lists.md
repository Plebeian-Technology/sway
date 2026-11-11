---
lat:
  mode: explanation
---

# Partial reload poll lists

Every page that refreshes itself asks the server for a fixed list of props through Inertia's `only:` option, and `spec/requests/partial_reload_contracts_spec.rb` makes the same request the browser makes and checks each named prop came back.

A reload that names a prop the controller no longer sends returns nothing for it,
and that part of the page goes quietly stale — the failure the whole
refresh-without-a-page-reload design exists to avoid.

## A partial reload has to carry the version header

The helper that makes these requests in a spec sends `X-Inertia-Version` alongside the partial-data headers, which the gem's own helper leaves out.

Without it the middleware answers 409 and asks the client to reload the whole
page — correct behaviour against a client holding a stale bundle, and wrong
about a request that is standing in for a browser that is not stale. A spec
using the gem's helper therefore tests the version mismatch rather than the
partial reload it meant to make.

## Why the Bill Creator tuples are read out of the TypeScript

The three Bill Creator tuples are extracted from the frontend constants at spec runtime rather than restated in Ruby, because a restated list is only correct on the day somebody writes it.

Both of the two lists that existed at the time had drifted.
`PIPELINE_LLM_ONLY_PROPS` had grown to thirteen names while the spec still listed
eight, and the summary-and-positions list to seven while the spec listed three.
The file carried a comment saying the lists had to be kept in sync, which is the
form of enforcement that fails silently: the five testimony props added to the
Pipeline tab were never covered by the contract that exists to cover them.

Reading `pipelineLlmOnlyProps.ts`, `BillCreatorSummary.tsx` and
`BillCreatorPositions.tsx` directly removes the second copy, and it is what
carried the contract through [[bill-creator-positions-tab]] splitting one of
those lists into two. [[spec/support/bill_creator_poll_props.rb#BillCreatorPollProps]]
raises rather than answering nothing when the declaration cannot be found or
holds no names, because an empty list would let every example reload no props
at all and still pass.

## Why the laziness example reloads the real tuple

The example proving the Bill Creator's props are built only when asked for reloads the tuple the tab actually polls, so what it demonstrates is what production does.

An earlier version reloaded the eight-name list and asserted the five testimony
props were absent from the response. That was true of the request it made and
false of every request the browser makes, since the live tuple names all five. It
described a saving nobody receives.

The assertion it can honestly make is narrower. Props the real tuple does not
name — the category scan, the locale legislator roster, the bill's legislator
votes, its campaigns and their organization candidates, the organizations list,
and the letter text of [[campaign-letter-disclosure]] — are absent from the
response and cost no query. The testimony props the tuple does name are still
computed on every tick, which is the cost the separate letter-text prop removes
for the letters specifically rather than for the tuple as a whole.

## What a tab's list has to carry besides its own props

A tab's `only:` list has to name every prop anything on the page reads, not
only the props that tab owns.

The run-conflict banner belongs to the shell rather than to either tab, and it
reads whichever run is truly in flight. If the in-flight run prop is left out
of a tab's refresh, the banner keeps rendering the run it last saw and a
finished run's banner sticks. The same applies to the campaign cards: polling
them without the approved-campaign decisions they display leaves an approved
stamp showing whatever the first page load said, however often the cards
themselves refresh.

The lists are also what the tests read. Recording every list the component
hands the poller lets an example check that the poll asks for the same props
the live connection names, rather than trusting that two hand-written lists
agree.

Naming props rather than reloading the page is also what preserves the control
that triggered the reload. Everything on the Influence page describes the
reader's standing in one jurisdiction, so switching locale replaces all of it;
listing those props by name keeps the page itself mounted, so the locale picker
is not rebuilt and does not lose keyboard focus mid-selection.

### A redirect already refreshes the page

A write whose response is a redirect needs no follow-up reload, because the
redirect Inertia follows re-renders the page by itself.

Asking for one anyway is a second request for a screen that has already been
replaced. Both the remove path and its neighbour used to do exactly that.

### Why the summary tab polls at all

Generate and Regenerate queue a plain background job with no pipeline run to
follow over the WebSocket, so a poll is the only thing that learns when the
answer lands.

The poller's presence on the page is therefore the whole start-and-stop signal,
which is why a test asserts both halves: that no new polling starts once the
condition ends, and that the previous poll's cleanup actually ran. Without the
second half a later break in that cleanup would leave a poll running forever
and nothing would notice.

## What the run-conflict banner counts as finished

The banner disappears on any terminal status, and the set of terminal statuses
is wider than the two obvious ones.

`succeeded` and `partial` were once missing from that check, and there is a
short window in which the prop still carries a just-finished run before a
reload clears it — long enough for the banner to claim a conflict that had
already ended.

A run whose worker died is a separate case again. It used to read as "in
progress" and offer only Cancel, which sounds like discarding live work, so
nobody pressed it and the run stayed stuck. Naming it as a run nobody is
working on is what makes the available action reasonable to take.

## Why an empty only list is not a partial request

Inertia decides a visit is partial by asking whether the `only` array has any entries at all.

An empty array therefore reads as "not a partial": no `X-Inertia-Partial-Data` header is sent, and the server builds and returns every prop the page has. Three call sites passed `only: []` meaning the exact opposite, and each of them was the most expensive request on its page rather than the cheapest.

Two shapes follow from that, depending on whether the request is wanted at all. When nothing on the server reads the parameter being changed, the whole round trip goes — the Notifications tab and the bill schedule calendar rewrite the address with `history.replaceState` instead. When the request genuinely has to reach the server, it names a real prop instead: the theme patch asks for `theme` back, which is both non-empty and the one prop the write actually changes, so the redirect it follows returns that and the always-props rather than the whole page.

A prop name that exists nowhere would shrink the response just as well, and was rejected: it reads as a mistake to anyone who greps for it, and it goes silently wrong the day someone adds a prop with that name.
