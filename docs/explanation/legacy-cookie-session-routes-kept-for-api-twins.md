---
mode: explanation
summary: "Why the cookie/session JSON routes for bill_scores, districts, legislators etc. look dead but are kept, since they front the same controllers as the API-key-gated scope \"api\" twins."
status: agent-extracted
related: []
---

<!-- vale Vale.Spelling = NO -->

# Why the top-level cookie/session JSON routes are kept

The top-level `bill_scores`,
`bill_score_districts`, `districts`, `influence`, `legislators`, and
`sway_locales` routes look dead — web uses Inertia props, mobile hits
top-level `/bills`, `/organizations`, etc (`mobile/src/api/routes.ts`) — but
they front the same controllers as the API-key-gated `scope "api"` twins
declared further below in `config/routes.rb`, for external/org consumers,
and cost nothing to keep.

If they are ever pruned, remove them as dead code; do NOT re-point internal
specs onto `/api`.
