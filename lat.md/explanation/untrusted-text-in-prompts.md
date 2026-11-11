---
lat:
  mode: explanation
---
# Untrusted text in a prompt

Everything Sway sends a model about a bill comes from somewhere else — a clerk's PDF, a resident's letter, an operator's paste — so a prompt builder's job is to keep that text from reading as instructions.

## Why every third-party value sits inside an enclosure

`Llm::UntrustedTextBlock` wraps outside text in a boundary tag carrying an unguessable suffix, so the model can tell Sway's own words from text somebody else wrote.

The rule is easy to apply to the obvious inputs and easy to miss on the rest.
`BillPositionsPromptBuilder` was hardened against a forgeable backtick fence
while `BillSummaryPromptBuilder` — which wraps the same kinds of content — was
left as it was, and the bill metadata and the citation allow-list on that side
carried third-party text outside the enclosure entirely, a fix the category
builder had already applied to the bill title. Collapsing whitespace blocks the
structural attacks and still leaves the our-prompt-against-their-text line
implicit, which is why a delimiter is used as well.

## Why the enclosure rewrites what it wraps, and what that costs

Wrapping is not passive: the enclosure rewrites code fences and anything that looks like a boundary prefix inside the text it is given.

That is what makes a forged boundary harmless, and it means a value that
survives the rewrite is not always the value that went in. A citation key
containing a boundary-shaped substring comes out of the enclosure changed, so an
exact comparison against the stored key reports a correct citation as invalid.
Such a key is dropped from the allow list rather than offered to the model in a
form it cannot honour.

## Why the two prompts keep their inputs apart

A bill summary and an organization's position are generated from different evidence on purpose, and the separation is pinned in both directions.

An earlier version let advocacy text reach the neutral summary, and the fix was
to remove that section rather than to soften what the summary was asked for.
The positions prompt runs the same rule the other way: it used to carry
testimony with nothing identifying the bill at all, a side effect of banning raw
bill text from it, and it now carries the bill's own summary as labelled
context instead.

Because the summary builder renders no supplemental-testimony section at all,
an example asserting that a blank value produces nothing proves very little on
its own. The check that carries the weight uses marker strings on all three
surfaces at once.

## Why a pasted document is treated like a fetched one

Text an operator pastes reaches the same builder as text a converter extracted, and it arrives without having passed any of the cleaning the extraction path does.

The main fix for broken glyphs happens at extraction, so supplemental testimony
typed or pasted into the admin form has had none of it. The builder is the last
gate before the substitution runs, which is why the delimiter checks are applied
there rather than assumed upstream.

## Why text is scrubbed before a regex reads it

Every builder cleans outside text before a pattern is run over it, because the wrapping raises on invalid bytes.

One builder did not, and a single bad byte in one document's name failed the
whole batch through a method-level rescue. The cost of scrubbing is nothing; the
cost of not scrubbing is every document in the batch.

## Why the model judges the document rather than its name

A document reaches the classifying model precisely because the filename rules could not decide from its name, so asking the model about that same name answers a question already known to be unanswerable.

The prompt therefore renders each document's extracted text, not only its
title — about a third of the corpus arrives undecided — and the check is made
against the payload the adapter actually receives rather than against what the
builder rendered, because a prompt that looked right while passing nothing
through was the defect.

The text half needs the protection more than the name half. A name is at worst
something a clerk accepted; a PDF body is whatever a member of the public
uploaded, so a boundary tag carried in the document text is redacted the same
way one in a name is.

## Why character caps stand in for token budgets

The caps in the builders are counted in characters, and what they are really bounding is tokens.

The two are not proportional. Measured with a real tokenizer, the same 150,000
characters of testimony came to 46,793 tokens on one bill and 86,767 on another,
so a character allowance has to be checked against the token budget it stands
for rather than assumed to track it. Uncapped, a large bill overflows the
model's context window — the largest Baltimore bills run 1.2 to 1.4MB of
extracted text — and the request is rejected with a 400 before the model runs
at all.

The cap also bounds memory, not just spend. The classifier shows the model at
most one document's worth of characters, so it reads a bounded slice of each
sidecar while classifying rather than holding whole documents: 200 candidates at
full size would be 100 million characters resident. Raising a cap can move the
binding constraint rather than remove it, and a composed cap cuts wherever it
lands in the joined text rather than at a document boundary.

Lengthening a repeated unit, rather than raising a cap, is what usually breaks
one of these: the probe text has to keep every registered boundary prefix inside
the per-document allowance.

## What a cacheable prefix needs

Anthropic's prompt cache only applies above a token floor, so whether a prefix is cacheable is a property of how long it has grown rather than a setting.

Both of the prefixes that matter crossed that floor as a side effect of other
work — the positions prefix when the bill-context wrapper was added, the
classifier prefix when the prompt stopped being a list of file names — so the
examples record which way each moved rather than asserting a fixed answer.

## Why an overshooting key list is deduped rather than refused

A response naming more citation keys than the ceiling allows is deduplicated first, because a repeat is not the same thing as an overshoot.

250 distinct keys plus one repeat is 251 items and 250 distinct keys, and
refusing it outright throws away a reply that has already been paid for.
Deduplication removes the repeat and leaves the ceiling meaning what it says.
