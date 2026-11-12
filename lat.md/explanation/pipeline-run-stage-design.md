---
lat:
  mode: explanation
---

# PipelineRunStage design notes

Explains why PipelineRunStage's serialized array columns declare no default in the model.

## Why the serialized array columns declare no model default

`completed_bill_external_ids` and `remaining_bill_external_ids` are declared with `serialize ..., coder: JSON` and no `default:`.

The database columns supply the `"[]"` default and the NOT NULL constraint (`db/schema.rb`), so the model's `serialize` declaration needs no default of its own.
