---
mode: explanation
summary: "Test-setup rationale for BillCreatorPipelineControls.test.tsx: why extra test blocks live in this file rather than beside the component, and why they reuse the top-of-file @inertiajs/react mock."
status: agent-extracted
related: []
---

# BillCreatorPipelineControls test notes

These live here because vitest only picks up `**/__tests__/**/*.test.{ts,tsx}`
(vitest.config.ts), not a file next to the component.

No second @inertiajs/react stand-in: the top-of-file vi.mock keeps all real exports and
only replaces a few, so these tests reuse it via the router.post import below.

(`app/frontend/components/admin/creator/__tests__/BillCreatorPipelineControls.test.tsx`)
