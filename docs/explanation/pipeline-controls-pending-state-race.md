---
mode: explanation
summary: "Why usePipelineControlsState caches pending values instead of trusting props, and the click-loss race that caching had to fix."
status: agent-extracted
related: [pipeline-controls-state-url-contract.md]
---
<!-- vale Vale.Spelling = NO -->

# Why pipeline-controls state caches pending values

`usePipelineControlsState`
(`app/frontend/components/admin/creator/pipeline-controls/usePipelineControlsState.ts`)
keeps `selected_stages` and `download_missing_assets` synced to the URL,
which is the single source of truth: setters push a new value into the URL
by visiting it, and the server sends that value back as props on the next
render.

## Why a pending-value cache exists at all

The push to the server is held back for a short debounce
(`URL_PUSH_DEBOUNCE_MS`, 250ms) so that a burst of clicks — ticking through
several pipeline stages in a row — collapses into one round trip instead of
one per click. But waiting 250ms before the checkbox visibly reacts would
feel laggy, so the hook also holds a pending value in React state. A setter
call flips the pending value at once, and the checkbox reflects
`pending ?? propValue` — instant on screen, with the URL catching up a
moment later.

The pending value is cleared on the next setter call, and also when the
render notices the server's own value has changed since the last time it was
compared — both done directly during render rather than inside a
`useEffect`, because this project's lint rules forbid setting state from an
effect. This is React's documented pattern for deriving state from props
across renders (storing information from previous renders), and every
`setState` call in that path sits behind a `!==` guard so it cannot spin into
an endless render loop.

## The race this design fixes

Before the pending-value cache existed in its current form, unchecking two
stage boxes with a short pause between them could lose the second uncheck.
The first uncheck's URL update went out during the pause; its answer —
describing the world as it stood one click earlier — landed after the second
click and overwrote it. The operator would see a box tick itself back on, or
would not notice at all and run the pipeline against a stage selection they
believed they had already changed. In the browser suite this showed up as
`fetch-hearings` turning up in a run it had just been unchecked out of, in
roughly one run in three. Two earlier fixes aimed at how fast clicks were
sent; neither helped, because click speed was never the cause.

**The fix's governing rule: a change not yet sent is newer than any answer
that can arrive.** The hook tracks whether its debounce timer is currently
armed (`changeNotYetSent`). The timer is armed by every setter call and
cleared once the push actually goes out, so an armed timer means the
operator has done something the server has not been told about yet — and
nothing arriving from the server right now can possibly be a reply to that
change. While the timer is armed, an incoming prop update is not allowed to
clear the pending value, so the second uncheck in the example above survives
until its own push flushes.

## usePipelineControlsState.test.ts notes on the debounce

The wait rolls a flurry of clicks into one visit. Without it, every
checkbox tick asks the server for a fresh preview and a fresh check of
which artifacts exist — clicking quickly through all seven checkboxes
costs seven database round trips before things settle. Waiting 250ms
after the last click collapses the burst into a single visit, and the
controls still respond instantly, because what they show comes from the
local copy until the server's answer gets back.

## usePipelineControlsState.test.ts notes on pending-override reconciliation (WR-NEW-02)

The hook keeps a local copy of the operator's click, so the checkbox
flips at once. That copy used to live forever — even after the server
sent the same (or a cleaned-up) value back. The next click in a burst
then worked out its new list from the stale copy instead of the server's
version, and the two drifted further apart with every quick click.

The fix is to spot the changed prop during render, NOT in a useEffect.
See the hook itself for React's "storing information from previous
renders" pattern:
https://react.dev/reference/react/useState#storing-information-from-previous-renders
When the server's value arrives, matching or correcting the local copy,
that copy is dropped in the very render that notices the change, behind a
`!==` check so it cannot loop forever.

## usePipelineControlsState.test.ts notes on full snapshot on partial change

`pendingValuesRef` is filled in when the hook mounts and then patched one
field at a time. Changing one field after the server has changed the
OTHER must send the current values, not the mount-time value of the field
nobody touched.

### The narrower race left behind

One race remains, and is considered acceptable: an answer to an *older* push
can still arrive after the *newest* push has already gone out, with the
timer already clear at that point (nothing left pending). In that case the
stale answer is briefly visible, but it self-corrects as soon as the newest
push's own answer lands — no click is lost, unlike the case above where the
loss was permanent until the operator's next interaction.
