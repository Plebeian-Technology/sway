---
mode: explanation
summary: "Test-setup rationale for BillCreatorPipelineLlm.test.tsx: why section order is pinned as a hard failure, and why every child section is stubbed to a bare marker div."
status: agent-extracted
related: []
---

# BillCreatorPipelineLlm test notes

The panel's seven sections have a fixed top-to-bottom order. If that order
ever changes by accident, this test MUST fail.

Every child section is replaced with a bare div carrying `data-testid="section-<Name>"`,
so the test reads marker order in the page — a change inside any child can't break the
ordering check.

Each stand-in draws a single div with a section-* testid, so the panel's children have a known order to check.

(`app/frontend/components/admin/creator/__tests__/BillCreatorPipelineLlm.test.tsx`)
