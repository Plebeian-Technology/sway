---
mode: explanation
summary: "Why a constant shared across examples in a spec file is declared above the describe block rather than inside it"
status: agent-extracted
related: []
---

# Why shared spec constants sit above the `describe` block

`spec/requests/admin/bills_pipeline_llm_activity_log_spec.rb` declares
`EXPECTED_ENTRY_KEYS` at the top of the file, above `RSpec.describe`, rather
than inside it.

A constant defined inside a `describe` block lands on `Object` anyway — Ruby
does not scope constants to RSpec's block structure the way it scopes local
variables. Declaring it at the top level instead of inside the block makes
that plain, rather than implying a scoping the language does not provide.
