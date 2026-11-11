---
mode: explanation
summary: "Explains SummaryCitationValidator's single entry point, why the three shapes of cited_section_keys (absent/empty/present) mean three different things, and why Result computes valid? instead of storing it."
status: agent-extracted
related: [bill-summary-call-preconditions]
---

# Why `SummaryCitationValidator` has one entry point and three verdicts

`SummaryCitationValidator` checks the section keys a summary written by an
LLM (large language model) claims to cite against the bill's real parsed
sections (its `BillSectionReference` rows). A cited key must match a
parsed key exactly. It is plain Ruby: it writes nothing to the database and
calls no model. `GenerateBillSummaryJob` uses the result to fill in
`citations_valid` and `invalid_citations`.

## The one allowed entry point

Callers go through `.verdict_attrs`, which itself uses the one allowed
instance form, `SummaryCitationValidator.new(bill:, cited_section_keys:).call`.
There are no other entry points on purpose -- no class-level `.call`, no
bare readers on the validator instance.

Two callers used to each decide on their own whether the payload had been
checked at all, and their hand-copied pre-checks drifted into opposite
meanings for the same payload -- each with a passing spec. That decision
now lives in exactly one place; `.verdict_attrs` performs the instance call
verbatim and adds nothing else.

## Why presence, not truthiness, decides the verdict

`.verdict_attrs` is the one place that decides "was this summary's
citation list checked at all?" -- every writer of `citations_valid` /
`invalid_citations` goes through it.

What matters is whether the `cited_section_keys` key is PRESENT in the
payload, not whether its value is truthy or empty. The three cases mean
three different things:

| Shape | Meaning | Verdict |
| --- | --- | --- |
| key absent | Nothing was cited, so nothing was CHECKED. This is the normal case, not a rare one: the prompt tells the model to leave the key out when the bill has no parsed sections, which is every bill with nothing to cite against. | `nil`, not a clean `true` |
| key present, `[]` | The model claimed "I cite nothing". That claim can be checked, and nothing it cited is wrong. | clean (`true`) |
| key present, `[..]` | Check each key against the bill's `BillSectionReference` rows. | computed |

The absent case sets BOTH `citations_valid` and `invalid_citations` to
`nil` instead of leaving them alone: an old verdict describes the summary
body this call just replaced, so keeping it would either claim unchecked
text is clean or keep naming a key the new body no longer contains.

## Why `Result#valid?` is computed, not stored

`#valid?` is computed from `invalid_citations` instead of being stored as a
second field -- one source of truth, so the two can never disagree.
`Result` is a named subclass (`Struct.new(:invalid_citations)`, not
`Struct.new` plus a block) so Steep, the Ruby type checker, can match
`#valid?` against the RBS class body instead of an opaque `class_eval`
block.

## Why an empty allow-list needs no special case

`#call` handles a bill with zero `BillSectionReference` rows with no
special case: against an empty allow-list, every non-empty
`cited_section_keys` entry is correctly marked invalid.
