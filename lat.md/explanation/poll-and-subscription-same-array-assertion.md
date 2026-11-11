---
lat:
  mode: explanation
---

# Why the poll/subscription tests check object identity

`Bill.test.tsx` and `BillOfTheMonth.test.tsx` both assert that the `only` array `usePoll` was called with is the same array object that `useScoreSubscription` was called with (`toBe`, not `toEqual`).

One `POLLING_PROPS` constant, declared at module level, feeds both hooks, so a refresh set off by the poll and one set off by a WebSocket push ask for exactly the same props — the very same array object. Asserting identity rather than just equality is what catches a future edit that accidentally gives the poll and the subscription two separately-built lists that drift apart over time.
