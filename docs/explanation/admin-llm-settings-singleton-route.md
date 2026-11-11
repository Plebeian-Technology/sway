---
mode: explanation
summary: "Why the admin LLM model selector is a singular resource with only #show and #update, and why namespace :admin has no shared base controller."
status: agent-extracted
related: []
---

<!-- vale Vale.Spelling = NO -->

# Why `llm_settings` is a singular resource

The admin Inertia surface for selecting the active Claude model for
`GenerateBillSummaryJob` is a singular resource — no `:index`, no `:id`
segment. `AdminSetting` is a singleton AR row, so `#show` + `#update` is the
whole surface.

`Admin::*` controllers inherit `ApplicationController` directly; there's no
`Admin::BaseController`.
