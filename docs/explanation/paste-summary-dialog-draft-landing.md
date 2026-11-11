---
mode: explanation
summary: "Explains why a pasted summary lands as a draft beside the editable box rather than inside it, and the two frontend bugs a browser spec caught that request specs could not."
status: agent-extracted
related: [bill-summary-published-vs-draft-box-bug.md, bill-summary-paste-hand-off-rule.md, ../reference/bill-paste-summary-response-outcomes.md]
---

<!-- vale Vale.Spelling = NO -->

# Where a paste lands, and why it moved

`PasteSummaryService` writes `bill_llm_provisioning.llm_summary` and never
`bills.summary`. The editable box holds `bills.summary` — the split
established by the fix in
[the published-vs-draft box bug](bill-summary-published-vs-draft-box-bug.md)
, which found that seeding the box from the draft column and saving
it to the published column let one press of Save replace a hand-written
public summary with the model's draft.

So a paste is a DRAFT: it appears beside the box, in `LlmSummaryDraftNotice`,
with one button that copies it in, and publishing it stays a deliberate act.
The refresh contract this dialog exists for is unchanged and is still
asserted, at the place the text now appears: the operator sees their paste
with no manual reload. What carries it there is no longer an
`llm_generated_at` remount key — the notice reads `llm_summary` as a prop,
and `#paste_summary` answers with a redirect that Inertia follows before the
dialog closes.

## Two bugs only a browser could catch

`spec/requests/bills_paste_summary_spec.rb` already covers the dialog's
server-side contract in full. Two frontend bugs turned up only when a person
clicked through the dialog, and neither shows up in a request spec:

1. The dialog closed even when the server rejected the paste. A rejection
   comes back as a redirect with the errors in the flash, and Inertia counts
   a redirect as success, so the error handler never ran. The fix reads
   `flash.paste_summary_errors` inside the success handler and keeps the
   dialog open with the errors listed (see `PasteSummaryDialog.tsx#onSuccess`).
2. The summary text did not refresh after a successful paste, so an operator
   had to reload the page to see their own work.

## Test setup: naming the published summary, and why the fixture is a real string

`spec/system/bills_paste_summary_dialog_spec.rb` names its published-summary
fixture (`published_summary`, a literal string) rather than leaving the
bill factory's default in place. The bill factory fills `summary` with a
Faker paragraph, which is how the wrong-column regression this file's DOCREF
pins read as unrelated noise rather than as a column that had changed
underneath the test. Naming the fixture makes every assertion about the
published column legible, and lets the examples state directly that a
paste must never move it.

## Test helper: why the validate-button wait is load-bearing

`paste_summary_json_and_validate` types the JSON into the dialog, waits for
the Validate button to become enabled, THEN clicks it. Validate stays
disabled until React has taken the pasted text, and Capybara's `#set`
returns before React re-renders — a click landing in that gap hits a
disabled button and sends nothing. The wait is folded into the shared
helper specifically so a future example cannot be written without it.

## Test setup: why the happy-path fixture needs both drafts and testimony

The `before` block's provisioning row has to exist at all, or the LLM
summary section never shows the button that opens the Paste Summary
dialog in the first place.

## LlmSummaryDraftNotice field notes

The editor used to seed from `llm_summary` and save to `bills.summary` —
two different columns — so any save replaced a hand-written public summary
with the model's draft.

Nothing is drawn when the draft matches the published summary.

`PasteSummaryService` writes only `llm_summary`, so an operator paste used
to say "The model wrote a different summary" — naming a model it never
touched. Wording now follows `llm_provider`.

Its `publishedSummary` prop (`bills.summary`) is what the draft compares
against — THIS, not the editor's live value: comparing against editor
state made the notice vanish on Copy, before Save had run.

## Test notes

This notice is where a PASTED summary lands: `PasteSummaryService` writes
`llm_summary`, never `bills.summary`, so between paste and
publish the operator's own text shows only HERE.

Every test passed while the notice mislabeled the text: the column move
was covered only at unit level, and only a browser test renders paste and
summary box together.

Either way the operator is told the same two facts, because they are what
decides what to do next: the text is not live, and one click puts it in
the box that is.

Comparing against the EDITOR's live text made the notice vanish the
instant "Copy draft into box" ran, before Save — falsely implying the copy
alone had published it.

Simulates the moment right after "Copy the draft into the box": editor
text now equals the draft, but the published summary has not been saved
yet.

The completed view puts `PasteSummaryDialog` and `LlmSummaryEditableSummary`
on the page, and both read Inertia's page props and router. Neither is
what these tests are about.

The wiring, not the wording: `llmProvider` passes through two components,
and a hard-coded null at either hop restores the wrong label with the
wording tests above still green.

The happy-path example's `before` block creates the provisioning row with
`:with_drafts`, which brings testimony along with it, for two reasons.
Without testimony on the bill, `PasteSummaryService` throws away the
payload's `draft_org_positions` and logs `positions_ignored_no_testimony`
— which would quietly turn the happy-path example into a test of the drop
path instead, without anyone deciding that on purpose. (The drop path gets
its own example, `REAS-01`, with the testimony cleared deliberately.)
Second, the happy path proves the pasted positions REPLACED an earlier
set, so an earlier set has to already exist — `:with_drafts` is that set.
These drafts used to arrive free with the `:completed` trait, which is how
this file once ended up testing drafts with no testimony at all.

## Test fixture: why the pasted org name is not "Test Org"

The happy-path payload's organization is named "Pasted Coalition" rather
than "Test Org." `:with_drafts` already seeds a draft under the name "Test
Org," so a payload reusing it would draw the same card whether the paste
was saved or thrown away with the old set left in place — an assertion
that could never fail either way. "Pasted Coalition" appears on screen
only if `PasteSummaryService` really wrote the pasted positions.

## Test design: the happy-path example also proves positions replace the old set

Checking only the summary textarea in the happy-path example is what once
let it keep passing after the service started dropping
`draft_org_positions` on a bill with no testimony — the one browser-level
"happy path" was really demonstrating the drop path while calling itself
acceptance. The example now also asserts that the pasted position's card
appears, that the old `:with_drafts` seed card is GONE (proving the write
replaced the set rather than the drop path leaving the old set untouched),
and that no "positions dropped" notice appears.

## Test design: asserting the error list before the still-open dialog

The reject-path example checks the error list appears before asserting the
dialog is still open. "The dialog stays open" is already true before the
click — it was open on the line above — so checking that first would pass
whether or not the click ever reached the server, and Capybara would never
wait for anything. The error list is the first thing that can only exist
after the server has answered; once it is on screen, the dialog still
being open is a real claim about a rejected paste rather than a restatement
of the setup. The reject payload itself breaks the schema by omitting the
required `summary_markdown` — `draft_org_positions` is optional in
`BILL_SUMMARY_SCHEMA` now, so a payload that left out only that field would
still validate.
