---
lat:
  mode: explanation
---

# Why stub_pipeline_success answers two different LLM calls differently

`GenerateBillSummaryJob` no longer goes through the old Python service; it calls llama.cpp directly using the `ruby-openai` client.

`AdminSystemHelpers#stub_pipeline_success` stands in for `OpenAI::Client` so system specs can run the job right there and then, without a real llama.cpp server.

ONE RUN MAKES TWO DIFFERENT CALLS, and this helper used to answer both with the same response body. A later change split the positions out of the summary contract: the summary call validates against `bill_summary.json` and the positions call against `bill_positions.json`, which REQUIRES `draft_org_positions` and refuses any other key (see `docs/explanation/bill-llm-schema-validation-design.md`). So the summary body handed to the positions call failed validation every time — absorbed silently by the job's own rescue, which is exactly why nothing noticed. `org_positions:` rode inside the summary body, where the job had stopped reading it, and the argument had quietly become a no-op.

The stub now tells the two calls apart the way the real adapter does: by the `json_schema` name it puts in the request (`parameters.dig(:response_format, :json_schema, :name)`). That keeps one seam, drives the real adapter code, and validates the answers for real rather than trusting whichever payload the stub happens to return.

The job records `llm_provider` and `llm_model` itself instead of reading them from the model's answer, so neither belongs in either stand-in response body.
