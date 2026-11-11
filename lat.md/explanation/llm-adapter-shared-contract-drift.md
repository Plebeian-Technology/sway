---
lat:
  mode: explanation
---

# Why the LLM adapter error-classification shared example exists

`Llm::ClaudeAdapter` and `Llm::LlamacppAdapter` are two implementations of the same agreement — see [[docs/reference/llm-adapter-error-classification.md|../reference/llm-adapter-error-classification.md]] for the exact clauses.

Both adapter files said so in comments, "they change together or they drift apart," but nothing enforced it.

The three clauses were spelled out by hand in two separate spec files with no shared group anywhere, and one clause had already drifted once: the blank-body check was fixed on the llama.cpp side, with three whitespace examples added there, and none added on the Claude side. The same drift could happen again in the untested direction with both suites green.

`spec/support/shared_examples/llm_structured_output_adapter.rb` closes that gap: one shared example, included from both adapters' specs, so a future fix to one side's blank-body handling (or any other clause) fails the other side's suite immediately if it is not mirrored.
