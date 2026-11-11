---
mode: explanation
summary: "Explains how BillPositionsPromptBuilder encloses testimony and bill-context text so untrusted content cannot be mistaken for instructions or forge a bill identity."
status: agent-extracted
related: []
---

# How BillPositionsPromptBuilder defends the prompt against outside text

<!-- vale Vale.Spelling = NO -->

`BillPositionsPromptBuilder` embeds two kinds of text nobody at Sway wrote:
public hearing testimony, and a generated bill summary built from bill text
that itself contains public testimony. This document explains how the
builder keeps that text from being mistaken for instructions, or from
forging a bill identity. See also
`docs/explanation/bill-summary-prompt-security.md` for the sibling
builder's version of the same problem, and
`docs/explanation/bill-positions-prompt-architecture.md` for the overall
prompt structure.

## Two enclosures, sharing one implementation

Testimony reaches this builder through a channel anyone can write to — any
member of the public may submit a PDF to a Baltimore City Council hearing.
The machinery that defends against that (a random delimiter per instance,
defusing backtick fences, blanking out anything resembling the boundary
whatever its letter case) lives in `Llm::UntrustedTextBlock`, so this
builder shares ONE implementation with `BillSummaryPromptBuilder`, which
wraps the same kinds of untrusted content.

`TESTIMONY_DELIMITER_PREFIX` names the testimony enclosure.
`CONTEXT_DELIMITER_PREFIX` is a SECOND, deliberately different enclosure for
the bill summary: it is model output built from bill text anyone can write
into, so it is untrusted for the same reason testimony is. Both prefixes
live in `Llm::UntrustedTextBlock::PREFIXES`, not as private strings — a
block blanks out every prefix the registry KNOWS ABOUT, so the two
enclosures this builder puts in ONE prompt defuse each other's tags as well
as their own. Using one delimiter for two blocks would make "opens once and
closes once" false for both, and that count is what makes a faked closing
tag noticeable.

## The bill-context section: an unconditional identity, plus an optional summary

`#bill_context_section` exists so the model can work out what testimony
means by "this measure" or "the proposed ordinance", and can tell a stance
on THIS bill from a stance on some other bill mentioned in passing.

THE IDENTITY IS UNCONDITIONAL; the summary is added only when there is one.
The whole section used to be dropped when `llm_summary` was blank, which
made the remedy conditional on the one value that is deliberately absent in
the case that needs it most: `GenerateBillSummaryJob` skips the summary
call for a bill with no diff markdown and no extracted text, and then runs
positions anyway — making the bills where positions is the ONLY output of a
run exactly the bills whose prompt named no bill at all. A Baltimore
hearing packet covers a docket of several bills, and an approved draft
becomes a public `OrganizationBillPosition`, so a stance routed to the
wrong bill is a published claim about a named organization.

Two short labels, not bill text. The "1.2-1.4 MB would drown the evidence"
argument (see `docs/explanation/bill-positions-prompt-architecture.md`) is
about the bill's TEXT and does not reach a bill number and a title. Both
come from Legistar, so both go through `Llm::PromptLabel.collapse` and
their own bound, which keeps each on one line: a title that starts with
`## ` cannot fake a heading, and neither can crowd out the testimony.

ONE enclosure covers the whole section rather than one per part, for the
same "opens once, closes once" reason given above.

EVERY value inside this enclosure is a one-line label, the summary
included — see the next section. The identity labels are the markers the
prompt steers by, so anything sharing the block with them has to lose its
line structure or it can forge them.

The summary itself is the saved `llm_summary`, NOT bill text.
`GenerateBillSummaryJob` writes it in the same statement that records the
summary as paid for and then makes the positions call, so the association
is already loaded — reading it costs no extra query.

## Why the summary label is collapsed, and testimony is not

`#summary_label` renders the saved `llm_summary` as a LABEL, not as a
document — it runs `Llm::PromptLabel.collapse` before
`Llm::UntrustedTextBlock.neutralize`.

It used to ship as a bare `#neutralized`, which keeps line structure intact.
That put an untrusted value with newlines in it inside the ONE enclosure
that also carries the prompt's two structural markers,
`- Bill number:` and `- Title:` — while the header tells the model this
section "names the bill you are being asked about" and the output contract
says "Ground every position strictly in the `## Testimony` section".
Neutralize defuses fences and every registered boundary prefix, but it does
not touch `\n`, `-` or `#`, so a steered summary could print a second bill
identity at column zero and a second `## Testimony` heading — and an
approved draft is a PUBLIC claim that a named organization took a stance,
routed, in that case, to the wrong bill.

This is the same treatment `BillCategoryPromptBuilder#bounded_summary`
already gives the same column, for the same reason.

The collapse belongs in `#summary_label` and NOT in `#neutralized`, which
`#testimony_sources` also calls. For testimony, the document IS the
structure — squashing a witness statement's paragraphing would destroy
evidence the positions call is grounded on. Which side a value falls on is
settled by `.max_summary_context_chars`' own reasoning (see
`docs/explanation/bill-positions-prompt-limits.md`): "a summary long enough
to be cut here has already stopped being context."

`Llm::PromptLabel.collapse` scrubs first, so it REPLACES the
`Sway::Utf8.scrub` `#neutralized` used to do here, rather than adding a
pass. The neutralize step still runs before `#truncate_summary_context`
measures, which is the scrub-then-neutralize-then-measure order
established for testimony too, and it cannot undo the collapse:
`BOUNDARY_MARKER_REPLACEMENT` carries no whitespace.

## `#context_boundary_instruction`: the second enclosure paragraph

A second enclosure paragraph, for the second kind of content. The caching
rule holds the same way — the fixed prefix only, never the random
per-instance suffix, so this stays identical across bills.

## `#testimony_section`: an unforgeable close instead of a backtick fence

In place of a backtick fence, the testimony block is closed by a random
delimiter made fresh per instance that the content cannot guess, and any
backtick fence inside the content is defused so it cannot end the block
early (`Llm::UntrustedTextBlock`).
