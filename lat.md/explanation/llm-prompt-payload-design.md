---
lat:
  mode: explanation
---

# Why Llm::PromptPayload runtime-checks fields Steep already types

`Llm::PromptPayload` is a small read-only object holding the two halves of a prompt: the system text (cacheable) and the per-bill user message. Both adapters read it; `GenerateBillSummaryJob` builds it and passes it unchanged.

`Data.define` needs Ruby 3.2+, and Sway runs Ruby 4.0+. Both readers are `String`s that are never nil, which Steep enforces when types are checked.

## Why runtime checks exist on top of the type declaration

The runtime checks catch what Steep cannot see. A caller at runtime — a console session, a dynamic call, some future integration — could still pass `nil` or a non-`String`.

The adapter would then blow up much later inside `client.messages.create` with a confusing SDK error. Raising here names the field, so the error points at where the bad value came in.
