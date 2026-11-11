---
mode: explanation
summary: "Why withCarriedRunPin exists, why it carries only run_id instead of the whole query string, and how it differs from currentAddressWithout."
status: agent-extracted
related: [docs/explanation/pipeline-run-pin-vs-active-run.md]
---

# Why `withCarriedRunPin` carries one parameter, not the whole query

Picking an older run in the Bill Creator writes `?run_id=` into the
address, and that is the only thing holding the Pipeline tab on that run —
without it, the tab goes back to showing the newest run. Changing tabs
builds a fresh address out of the bill and the tab, so the pin was dropped
every time a tab changed, and an operator reading a failed run lost their
place the moment they looked at anything else. A background job is not
affected by any of this; only the screen forgot where the operator was.
`withCarriedRunPin` (`app/frontend/sway_utils/withCarriedRunPin.ts`) fixes
that by adding the pinned run back onto an address the caller has just
built from scratch.

## Why it carries one name and not the whole query

Sweeping every parameter forward would undo the removals other controls
make on purpose — the run dropdown clears `run_id` to mean "show me the
newest", and the activity log carries a position that belongs to the tab
being left. Absence and deliberate removal look the same to anything that
merges, so only the caller knows which it meant. `withCarriedRunPin`
carries only the one value the operator chose and that nothing else
restores. `currentAddressWithout`
(`app/frontend/sway_utils/currentAddressWithout.ts`) states the same rule
for the opposite direction: the caller owns what it says, and only the
caller knows it meant to say it.

It is added on every tab change, rather than only when returning to the
Pipeline tab, so that leaving and coming back puts the operator where they
were.

## Forward compatibility: a path that already names a run wins

A path that already names a run keeps the one it names — `withCarriedRunPin`
never overwrites an existing `run_id`. No caller builds a path like that
today, but a future caller might build one that already asks for a specific
run. Following a link like that means asking for that run, and the address
must not overrule it.

## Compare `currentAddressWithout`

`currentAddressWithout` is for a visit that starts FROM the address already
on screen — it strips parameters the visit owns and keeps everything else
by construction. `withCarriedRunPin` is for a caller that has deliberately
built a brand new path and wants exactly one value brought across.

For how the carried pin is read back out on the other tabs — and why it
must not be read as "the run currently in flight" — see
[pipeline-run-pin-vs-active-run.md](pipeline-run-pin-vs-active-run.md).

## Why "Don't Save + Reset to New" carries nothing forward

Carry nothing forward. Reaches the same empty picker as picking "New bill"
from the bill dropdown (BillCreatorShell's onBillChange), visiting this
same route with no query.

A pinned run, activity log cursor, and every other control's owned
parameter belong to the tab being left, not the new bill (see
withCarriedRunPin.ts for why).
