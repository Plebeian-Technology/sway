---
lat:
  mode: explanation
---
# Reading the instructions Sway sends the model

`/admin/system_prompts` shows the standing instructions Sway sends to a
model, rendered by the same builder classes the jobs use. It is read-only, and
carries no content from any individual call.

The catalog represents five distinct prompt purposes: bill summary, organization
positions drawn from testimony, bill categorisation, testimony attachment
classification, and kind-of-source classification. The bill summary prompt expands
into one card per active Sway jurisdiction (`SwayLocale`). On a standard installation
with three seeded jurisdictions (Baltimore City, State of Maryland, and U.S. Congress),
the catalog generates seven prompt cards. [[llm-summaries]] covers how those calls
are made and which adapter carries them.

Before the page existed, reading a prompt meant opening the builder class and
assembling its sections by hand, or running `Eval::PromptDump` against a local
database. Neither answers the question an operator has, which is what this
installation sends right now.

`AdminSystemPromptCatalog` holds the prompt entries in pipeline order and the two
model names they are sent under, so the page states the model beside each
prompt rather than leaving the mapping to be inferred.

## Why the standing instruction is the half worth showing

Every call is split into a system prompt and a user message, and the page shows
the system prompt alone.

The user message is one call's own content: a bill's metadata and diff, a batch
of hearing letters, the text extracted from an attachment. It differs on every
call, it is legislative material and public testimony rather than anything Sway
wrote, and rendering it would put that material on an admin settings page where
nobody would look for it. The system prompt is the opposite on all three
counts — fixed, written by Sway, and the same for every bill.

The page says so in its own copy, before the first prompt, because a reader who
takes the visible text for the whole request would draw the wrong conclusion
about how much a model is told. The copy claims only that these are rendered by
the same builders against the same category list, never that they are
byte-identical to the last real call: nothing on the page reads back a request
that was actually sent.

## Why the page is read-only

The five prompts change by a code change and a deploy. There is no form on the
page and no column behind it.

A runtime-editable prompt was considered and declined. Each of the five carries
the instructions that make up the prompt-injection defence — the paragraph
naming the enclosed material as data, the delimiter explanation, the output
contract the schema is checked against. An edit box past the admin gate would
put all of that one careless save away from being removed, with no review and
no test between the save and the next bill. That is a larger decision than
showing the text, and it is recorded here so a later reader does not read the
absence of an editor as an oversight.

## Why the category builder's system prompt became public

`BillCategoryPromptBuilder#system_prompt` sits alongside `#payload` rather than
below `private`.

The same String was already reachable as `payload.system_prompt`, so the
privacy was never a boundary — it followed from the class having shipped with a
single caller. Reaching it through `#payload` would mean the catalog also had
to construct a `user_message` out of a bill title and an LLM summary, on a page
whose whole claim is that per-call content is not shown. The other four
builders already expose `#system_prompt`, so making the fifth match lets the
catalog call the same method on all five.

## Why an unsaved placeholder bill is the right input

The catalog passes an unsaved placeholder bill to the three bill builders and an empty array to the two testimony builders. Nothing is saved and nothing is read from disk.

While `BillPositionsPromptBuilder` and `BillCategoryPromptBuilder` receive a bare `Bill.new`, `BillSummaryPromptBuilder` requires jurisdictional context to render its locale primer. The catalog passes `Bill.new(sway_locale: locale)` for each locale card.

A system prompt is built from constants, schema files, and live active categories. No builder reads database bills or documents while assembling its system prompt. Feeding a real bill would change nothing in the prompt output while making the catalog depend on database records existing.

`spec/services/admin_system_prompt_catalog_spec.rb` maintains that invariant by asserting that `BillSummaryPromptBuilder` produces identical prompts from `Bill.new(sway_locale: baltimore)` and from a persisted, fully populated Baltimore bill.

## Why the real active category list is used

The catalog loads the live active categories and hands them to the two builders
that take a list, rather than passing a fixed example set.

An empty or invented list does not abridge those two prompts, it swaps a branch
in them. `BillSummaryPromptBuilder` names every active category inside its
output contract and drops the `categories` key from the required-output JSON
when the list is empty. A page showing the wrong branch would be describing a
different installation.

## What the page shows when the taxonomy is empty

With no active categories the page renders four prompts normally and, in place
of the fifth, states that no categorisation prompt is sent on this
installation.

That is what production does, and the two jobs differ on the same input.
`BackfillBillCategoriesJob` loads the list, finds it empty, logs
`backfill_bill_categories.no_active_categories` and returns before any adapter
call. `GenerateBillSummaryJob` passes the empty list straight through, so the
summary prompt's "no active taxonomy" branch is genuinely what gets sent and
the page renders it verbatim.

The catalog checks the list before constructing `BillCategoryPromptBuilder`,
which raises `ArgumentError` on an empty taxonomy. Rescuing that error instead
would make the page's explanation a guess about why the constructor raised,
where the guard states the one condition the page reports.

## What the page shows when a locale lacks summarization instructions

When an active `SwayLocale` lacks an instruction row, its `legislative_body_makeup` is blank, or the locale is not declared in `SwayLocale::JurisdictionRulesRegistry`, the catalog withholds the prompt and marks the card unavailable.

The catalog checks whether `SwayLocale::JurisdictionRulesRegistry.declared?(locale.name)` is true and whether `locale.llm_bill_summarization_instruction&.legislative_body_makeup` is present before calling `BillSummaryPromptBuilder`. When either condition fails, the catalog does not invoke the prompt builder, avoiding missing-context warning logs during catalog generation and preventing prompts from rendering without required jurisdictional framing.

Instead, the catalog populates `unavailable_reason` with a descriptive message naming either `SwayLocale::JurisdictionRulesRegistry::DECLARATIONS` or the `llm_bill_summarization_instructions` table and the `SeedLlmBillSummarizationInstruction` seeder, setting `system_prompt` and `character_count` to `nil`. The frontend renders an informative alert and a "Not sent" badge, signaling that code declarations or administrative seeds are needed.

## Why the list is not deferred

All five prompts ship in the initial props rather than through
`InertiaRails.defer`.

They are the page's entire content, so deferring would render an empty screen
and then a second request to fill it. Building them costs two queries — the
active categories and the singleton settings row — and string interpolation.
No model is called and no file is read. The one write it can make is
`AdminSetting.singleton` inserting the settings row on an installation that has
never saved one.

## Why the query for active categories is spelled again here

`Category.where(active: true).order(:name).to_a` appears in the catalog as its
own memoized method, rather than through a shared scope.

Eight call sites now spell that query out, and four more spell a `pluck`, a
`map` or an unordered variant of it. Collapsing them into a scope is
worth doing and was deliberately left out of this change:
`spec/jobs/backfill_bill_categories_job_spec.rb` asserts the literal string
appears exactly once in that job's source, so the sweep has to move the spec in
the same commit, and a page that only reads the list is a poor place to start
it.
