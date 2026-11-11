---
mode: explanation
summary: "Explains what BillPositionsPromptBuilder assembles, why it reads only testimony as evidence, and why its prompt sections are named rather than positioned."
status: agent-extracted
related: []
---

# How BillPositionsPromptBuilder assembles the bill-positions prompt

<!-- vale Vale.Spelling = NO -->

`BillPositionsPromptBuilder` builds the prompt for the LLM call that works
out which organizations, or individuals, back or oppose a bill. See also
`docs/explanation/bill-summary-prompt-architecture.md` for the sibling
builder this one was split out of, and
`docs/explanation/bill-positions-prompt-security.md` /
`docs/explanation/bill-positions-prompt-limits.md` for how it defends
against outside text and where its size limits come from.

## The evidence is testimony, and nothing else

The EVIDENCE is testimony and nothing else:
`BillLlmProvisioning#extracted_testimony` and `#supplemental_testimony`.
Never the bill diff, the extracted bill text, or any other source. What the
model reasons from contains no diff content at all.

One input is not testimony: the generated `llm_summary`, added as clearly
labeled context. It is not evidence, and the output contract says so twice —
the model is told it may use the summary only to work out what the
testimony is referring to, never to guess a stance from it. It is there
because the prompt used to carry no bill identity at all, not even the bill
number, so the pointing phrases testimony is full of — "this measure", "the
proposed ordinance" — had nothing to point at.

Using the summary rather than the bill text is the whole design: at
1.2-1.4 MB against a few KB of testimony, the bill text would drown the
evidence; a capped summary cannot.

The answer must match `config/schemas/bill_positions.json`
(`BILL_POSITIONS_SCHEMA`) — one required key, `draft_org_positions`, whose
entries hold `org_name`, `stance` and `summary`. The schema sets
`additionalProperties: false`, so the prompt must never ask the model for
any other key.

## Two pieces, split the same way as the sibling builder

`#system_prompt` (`header` + `output_contract`) and `#user_message`
(`bill_context_section` + `testimony_section`) split the same way
`BillSummaryPromptBuilder` does, so `GenerateBillSummaryJob` can build an
`Llm::PromptPayload` from either builder in exactly the same way. The
system part fills in nothing that changes from bill to bill, which is what
lets it be cached; the user part changes per bill, which is exactly why it
cannot be.

## Why sections are named, not positioned

Where the prompt text refers to another part of itself, it names the
section — `## Required output`, `## Testimony` — instead of saying "above"
or "below". `#header` and `#output_contract` both do this, for two
different reasons that both come down to the same fact: the same text is
read under more than one ordering, so a directional word is only true under
one of them.

`#output_contract` sits inside `#system_prompt`, which puts it in the
MIDDLE of the assembled prompt — header, `## Required output`,
`## Testimony` — both under `#call` and under the API split
(`[system_prompt, user_message].join`). An earlier fix pointed
`#output_contract` at "above" or "below" and got it backwards: the
testimony is always BELOW this block, on every call, because both
consumers put the system part before the user part. "The testimony
provided above" was wrong every time.

`#header`'s reference to the bill-context section had the opposite problem:
an earlier fix corrected the direction for `#output_contract` and left this
one unchanged, so it stayed wrong in the OTHER direction — "at the end"
pointed past the contract at the testimony on every call, because the
contract sits in the middle, not at the end.

A heading name is correct under every ordering, and it keeps the cacheable
part of the prompt byte-for-byte stable. `BillSummaryPromptBuilder`'s
`#header` got the same fix for the same reason — see
`docs/explanation/bill-summary-prompt-security.md#why-the-header-names-sections-instead-of-saying-above-or-below`.

## Why `#call` is kept, even though nothing in production calls it

Both LLM adapters take an `Llm::PromptPayload` that `GenerateBillSummaryJob`
builds from `#system_prompt` and `#user_message` directly, so nothing in
`app/` or `lib/` joins the two. `#call` is kept anyway, as the whole-prompt
view for an operator or a console session — mirroring the sibling
builder's `#call`, which `BillsController#summary_prompt_prop` does serve
in production.

It is also the only place the testimony JOIN ORDER (see
`docs/explanation/bill-positions-prompt-limits.md`) can actually be seen
end to end, and it is what every spec in this file asserts against;
deleting it would cost a rewritten test suite and that visibility.
`Testimony::ClassificationPromptBuilder` deliberately has no `#call`,
because it had no spec either.

## `#system_prompt` and `#user_message`: which half is cacheable

`#system_prompt` is `[header, output_contract]` — the cacheable part of the
prompt, since header and output_contract fill in nothing that changes from
bill to bill.

`#user_message` is the per-bill part: the bill-context section, followed by
the joined and capped testimony. Neither can be cached, since both change
per bill — which is exactly why they live here and not in `#system_prompt`.
