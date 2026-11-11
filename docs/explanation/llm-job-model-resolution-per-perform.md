---
mode: explanation
summary: "Why GenerateBillSummaryJob and BackfillBillCategoriesJob re-resolve the LLM model on every perform instead of once at boot."
status: agent-extracted
related: []
---

<!-- vale Vale.Spelling = NO -->

# Why the model is re-read on every perform, not memoized

`GenerateBillSummaryJob#resolve_model_for` and
`BackfillBillCategoriesJob#resolve_model_for` both re-read the model on
every `perform`, so an admin's model change takes effect on the next job
without restarting the process.

Only the Claude branch reads a value that can change mid-process
(`AdminSetting`, a DB row). The llama.cpp branch reads
`Sway::Settings.llm`, memoized once per process at boot, and
recovers by redeploying like every other declared setting.
