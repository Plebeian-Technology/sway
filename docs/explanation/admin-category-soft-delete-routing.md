---
mode: explanation
summary: "Why the admin category CRUD route is a plural resource and why :destroy is a permanent delete gated behind a deactivate-first step."
status: agent-extracted
related: []
---

<!-- vale Vale.Spelling = NO -->

# Why admin category routes use a plural resource with a gated destroy

Admin taxonomy CRUD (`namespace :admin { resources :categories }`) is a
plural resource so `#index` is available — a singular resource has no
`#index` route.

`:destroy` permanently deletes a category, but the controller
gates it on `active: false` — deletion is a deliberate two-step (deactivate
then delete), leaving soft-deactivate (via `#update`) as the reversible
path.
