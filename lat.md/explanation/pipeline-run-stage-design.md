---
lat:
  mode: explanation
---

# PipelineRunStage design notes

Explains why PipelineRunStage's serialized array columns have no default.

## Why the serialized array columns have no default

`completed_bill_external_ids` and `remaining_bill_external_ids` are declared with `serialize ..., coder: JSON` and no `default:`.

Leaving the default unset keeps newly created stage rows `nil` rather than writing `"[]"` onto every row when nothing writes external bill IDs to the stage.
