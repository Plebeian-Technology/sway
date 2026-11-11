---
lat:
  mode: explanation
---

# Why UntrustedTextBlock keeps its prefixes in one registry

`Llm::UntrustedTextBlock` wraps outside text — bill source, hearing testimony, downloaded law text — in a boundary the model is told to trust.

Every block must scrub not only its own boundary tag but every other block's tag too, because a prompt can carry more than one block at once. If one block cannot see another block's tag, it cannot scrub it, and the unscrubbed tag can blur the second boundary.

`PREFIXES` is the single place that lists every kind of content this scrubbing applies to:

```ruby
PREFIXES = {
  testimony: "TESTIMONY-BOUNDARY",
  bill_context: "BILL-CONTEXT-BOUNDARY",
  bill_source: "BILL-CONTENT-BOUNDARY",
  document_contents: "DOCUMENT-CONTENTS-BOUNDARY",
  citation_keys: "CITATION-KEYS-BOUNDARY"
}.freeze
```

## Why a registry instead of an argument

The prefix used to be a plain argument that each caller passed in.

That design had a real bug: `BillPositionsPromptBuilder` puts two blocks in one prompt, and each block scrubbed only the prefix it was given. Neither block could forge the other's tag — the random suffix on each tag stays unguessable — but an unscrubbed tag still muddies the boundary the prompt tells the model to trust.

A registry fixes this by construction. An argument leaves each call site free to forget to pass the other prefixes in; a registry cannot be skipped, because `UntrustedTextBlock.new` refuses any prefix that is not already listed in `PREFIXES`. Adding a new kind of content means adding one line to the registry, and every existing block — not just the new one — starts scrubbing it.

## Case history: the fourth and fifth entries

The fourth entry arrived exactly that way.

Sway needed to enclose the numbered attachment list built by `Testimony::ClassificationPromptBuilder`. Adding one line to `PREFIXES` was the whole integration; every block already in production started scrubbing the new tag without further changes.

That entry was later renamed from `:document_names` to `:document_contents`, because what it labels changed: the block now encloses each document's extracted opening text alongside its name, not just the name. The registry's keys are meant to describe the material they cover, so a stale key would make the registry's central claim — "add a line and every sibling scrubs it" — impossible to check by reading the code.

Renaming a key deliberately throws away more than strictly needed: `ALL_PREFIXES_PATTERN` stops matching the retired string, and `Testimony::ClassificationPromptBuilder::PROMPT_VERSION` bumps by one so that documents get re-classified under the new label.

The fifth entry, `:citation_keys`, encloses the citation allow-list that `BillSummaryPromptBuilder` prints — the last section of that prompt whose boundary had been described only in prose, not enforced by a tag. Its rows are law-section keys and titles pulled from the downloaded law corpus, so — even though a human reader is meant to pick from this list rather than read it as free text — the rows still come from outside the system and still need the same enclosure.

Adding this entry was not free. It widens `ALL_PREFIXES_PATTERN`, and `ClassificationPromptBuilder` builds its own classification probe text from the same registry, so the fifth line also bumps `PROMPT_VERSION`, which re-checks any document that classification had not yet decided on. The team judged that trade an easy one: re-asking a bounded set of undecided documents costs less than leaving behind a verdict that nothing else can ever correct.

## Related

Cross-references to untrusted text wrapping mechanisms, prompt safety boundaries, and input sanitization services.

- `docs/explanation/bill-summary-prompt-security.md` — how
  `BillSummaryPromptBuilder` uses `UntrustedTextBlock` to defend its
  prompt against outside text.
