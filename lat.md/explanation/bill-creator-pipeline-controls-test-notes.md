---
lat:
  mode: explanation
---

# BillCreatorPipelineControls test notes

These live here because vitest only picks up `**/__tests__/**/*.test.{ts,tsx}` (vitest.config.ts), not a file next to the component.

No second @inertiajs/react stand-in: the top-of-file vi.mock keeps all real exports and only replaces a few, so these tests reuse it via the router.post import below.

(`app/frontend/components/admin/creator/__tests__/BillCreatorPipelineControls.test.tsx`)
