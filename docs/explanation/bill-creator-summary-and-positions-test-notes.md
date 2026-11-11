---
mode: explanation
summary: "Test-setup rationale for BillCreatorSummaryAndPositions.test.tsx: the usePoll mock's shape, StrictMode assumptions, and the mock's hook-lint-satisfying naming."
status: agent-extracted
related: []
---

# BillCreatorSummaryAndPositions test notes

## The usePoll mock's shape

usePoll is called from SummaryGenerationPoller, on the page only while a summary is generating — no
separate start/stop call or effect.

usePollMock counts calls (once per poller render, not per appearance); pollDestroySpy
records the cleanup usePoll's real effect return runs on removal.

StrictMode would double-count both fakes (mount→unmount→mount→unmount); the
toHaveBeenCalledTimes(1) checks below assume it's off, which Vitest 4 does by default.

The fake is written as a named function, `function usePoll(...)`, so React's
hook lint rule treats it as a hook. Otherwise the React.useEffect call inside
it would be reported as an error.

(`app/frontend/components/admin/creator/__tests__/BillCreatorSummaryAndPositions.test.tsx`)
