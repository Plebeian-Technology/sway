---
lat:
  mode: explanation
---

# Why the model is re-read on every perform, not memoized

`GenerateBillSummaryJob#perform` and `BackfillBillCategoriesJob#perform` both resolve the route through `Llm::RouteResolver.resolve` on every `perform`, so an admin's model change takes effect on the next job without restarting the process.

Only the Claude branch reads a value that can change mid-process (`AdminSetting`, a DB row). The llama.cpp branch reads `Sway::Settings.llm`, memoized once per process at boot, and recovers by redeploying like every other declared setting.
