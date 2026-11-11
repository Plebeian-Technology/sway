---
mode: explanation
summary: "Why a live integration spec against llama.cpp pins down that response_format: json_schema conforms to BILL_SUMMARY_SCHEMA where the plainer json_object form can drift on small models."
status: agent-extracted
related: []
---
<!-- vale Vale.Spelling = NO -->

# Why the llama.cpp response-format spec exists

`spec/integration/llamacpp_response_format_spec.rb` is a live integration
spec: it talks to a real llama.cpp HTTP server wherever
`LLAMACPP_BASE_URL` points (`host.docker.internal:8888` in dev). It skips
itself when the server cannot be reached, so CI and offline work never
fail over a dependency that lives outside the repo.

## What it pins down

Sending `response_format: { type: "json_schema", json_schema: {...} }`
gets back output that matches `BILL_SUMMARY_SCHEMA`. The plainer
`json_object` form, which `GenerateBillSummaryJob` sends today, only
promises the reply is valid JSON — it does not constrain the grammar to
the schema's keys. Small models such as gemma-3/4-E2B drift into
returning valid JSON with the wrong key names (`llm_summary` instead of
`summary_markdown`, for example), which then fails schema validation
further down the line. The `json_object` example in this spec is a
baseline, not a contract: it records what the model really returns when
nothing constrains its grammar, so there is something concrete to work
from while tuning the prompt.

## Why it is kept apart from the job spec

`spec/jobs/generate_bill_summary_job_spec.rb` stubs out `OpenAI::Client`
completely. This spec exists specifically because that one cannot exercise
whether the real llama.cpp server's grammar-constrained generation
actually produces conforming output — here the request really goes over
the network.
