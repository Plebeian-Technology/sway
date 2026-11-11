---
lat:
  mode: explanation
---

# Why llm_settings is a singular resource

The admin Inertia surface for selecting the active Claude model for `GenerateBillSummaryJob` is a singular resource — no `:index`, no `:id` segment.

`AdminSetting` is a singleton AR row, so `#show` + `#update` is the whole surface.

`Admin::*` controllers inherit `ApplicationController` directly; there's no `Admin::BaseController`.
