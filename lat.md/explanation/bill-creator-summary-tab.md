---
lat:
  mode: explanation
---

# The Bill Creator summary tab

The summary tab is where an operator reads what a model wrote about a bill, decides whether it is fit to publish, and works through the organization positions the same run produced. Its layout says which of those two jobs each control belongs to.

## Planned recoverable summary history

Planned immutable revisions preserve summary text across model generations, operator edits and restores. The admin history view exposes those versions without changing the current text merely by opening one.

Generated drafts and published summaries remain distinct. Each revision retains exact Markdown, time, origin, known actor, actual provider/model where applicable, review state and the source revision of a restore. Unknown legacy provenance stays unknown. Review state belongs to the captured revision; comparison with the latest generated text cannot establish whether an older version was reviewed. The latest prompt snapshot remains a record of run inputs rather than becoming a substitute for revision storage.

Storage precedes generated-result capture, operator-write capture, read-only history and explicit restoration. Accepted synchronous and batch generations share capture semantics through the persist guard, including drafts withheld from publication. Operator edits and accepted pastes preserve committed changes rather than recording keystrokes or local draft autosaves. Retries, unchanged saves and failed transactions do not create misleading history.

History loads selected bodies on demand rather than adding them to five-second polling props. Restoration persists exact selected text as the public summary, appends a new restore revision and retains intervening history. Same-bill authorization, truthful AI provenance and concurrent-generation protection remain necessary because restoring text is an operator publication choice, not a fresh model generation.

Manual publication commits atomically with its history, retaining distinct legacy generated drafts before replacement, and coordinates restoration with late generation under fresh locked publication state. On a first edit, failed `operator_edit` revision capture rolls back both the initial baseline and the summary update. Published review status follows revision provenance rather than equality with the latest draft. The history control belongs to every persisted bill with revisions, including manual-only bills without generation provisioning.

## Where the summary stops and the positions start

The tab's sections are told apart by the kind of container each one is, rather than by a repeated heading treatment: a raised panel, an open working region, an inset sub-panel and a quiet region each say something different about what they hold.

Every level of the tab once opened the same way, with a micro-caps eyebrow over a hairline rule in `border-soft`. That rule was about a one-percent difference in lightness against the ground it sat on, which is below the threshold at which an edge reads as an edge, so on a real screen it did not render at all. What remained was a row of small capitals, identical at the section, sub-section and field levels, carrying the entire burden of saying which of them was which — and small capitals are the one setting that resists being scanned quickly, because the word shapes that ordinarily distinguish one heading from another are flattened into rectangles of the same height.

The type ladder carries the levels now. A section opens at `text-lg font-semibold` in sentence case, a sub-section at `text-base font-medium`, and helper text sits at `text-xs` in the muted colour without italics. All-capitals survives on status badges alone, where the word is a stamp rather than something to read.

The Public summary panel is the one surface on the tab that lifts off the page — a card fill, a strong border and the hard shadow — because it holds the artifact being published, and every other control on the screen exists to change it or to decide whether it is fit to go out. Testimony and positions is an open region instead, opened by a heavy rule and its own heading with its children indented, since it is a place of work rather than a thing. Categories and Supporting / opposing arguments are quieter still, opened by a lighter rule, because each one is a short list an operator visits after the summary is settled.

## Why the panel lists what the model reads

Under the Public summary box, above the full breakdown, a ledger names each input a summary run reads and how much of it got in: the bill's details, one source text, the law sections it may cite, and the local news it may cite.

A summary can only be judged against what the model was given, and until this ledger nothing on the tab said what that was. The prompt reads one source text and chooses it in a fixed order — the diff against existing law, else the bill's own extracted text, else nothing, in which case the model is told to fetch the text itself — and the row for the source says which of the three it got, how long it is, and whether the size cap cut it. Where a diff file exists, a line under that row names how many sections the stored diff record amends, how many it merely references, and how many it names but could not be found in the law corpus, because "diff" on its own covers outcomes that are nothing alike. In the development corpus 92 of the 204 bills carry a diff that modifies at least one section — one of them modifies twenty-two, references one and fails to find one — and the remaining 112 carry a diff that modifies none, which is a diff the model read as context and nothing more.

The rows are listed in the order the prompt renders them, and the ledger is a list rather than a set of cards for that reason: the order is the precedence rule, and cards of equal weight would hide it. Each row carries a plain sentence rather than a figure with a label, since the useful fact is a comparison ("the bill's own text is on file, but the diff takes its place") that a number cannot carry.

The counts come from `BillSummaryPromptBuilder#sources`, which the builder derives from the same row sets its own sections render, so a row and the prompt cannot disagree — with one exception the panel names where it renders it, in [[bill-creator-summary-tab#Why the diff counts are attributed to a record]]. `SummarySourcesReport` adds the dates and the newsroom list around those counts. It reports two readings: `read`, the counts stored by the run that produced the summary, and `now`, the same counts computed for the bill as it stands.

News is the row most likely to read as empty, and it says why in each case: no newsrooms are set up for the jurisdiction, the local model cannot search the web, the next run will search, or a search ran and found nothing. Newsrooms are counted by outlet rather than by listed address, since one outlet can be seeded under several paths. The ledger carries titles and outlets only; no article text, bill text or law text crosses to the page through it.

The panel is headed "What the model read" and prefers the recorded reading everywhere. Where `read` is present the rows carry the counts stored at run time, and a line under the heading names the run's date and the model that read them. Only where no snapshot exists do the rows fall back to `now`, under a marked notice saying that nothing was recorded and that the rows are what a run would read today. Most bills are in that second state, so the fallback is what an operator meets first, and it is labelled rather than dressed up as a record.

Two unrecorded cases are not the same thing, and the notice tells them apart. A summary an operator pasted by hand was read by no model at all. A summary a model wrote before Sway kept the record had a run, whose inputs are simply gone. Calling the second a paste, or the first a lost record, would each misstate who wrote the text in the box.

The stamps follow the reading. In the recorded reading each row compares its own stored facts against the same facts computed now and carries "Changed since run" where they differ — the source's kind, size and diff date on one row, the citation counts and sampled titles on the next, the news search and its articles on the last. "Newer than summary" belongs to the unrecorded reading, where there is no stored half to compare against and the summary's own date is the only reference point left. The Bill details row carries no change stamp at all: the record keeps no counts for the metadata section, so nothing there can be compared without opening the text.

The law row counts list rows rather than distinct sections. `citation_keys_offered` counts what the allow list renders, and a bill can name one key several times — bill 11 offers `art_6__sec_6-10` four times under a single title — so the row says "repeats counted" and never implies four sections. The titles beside it are named as a sample for the same reason: `SAMPLE_TITLE_COUNT` caps them at three, so a count of four beside three titles is the cap doing its work rather than a fourth title gone missing.

The panel closes with a line saying that testimony and organization positions are not sent to the model. It is the one question the four rows cannot answer by listing what is there, and the prompt is explicit about it: the header instructs the model that testimony, advocacy and statements of position are deliberately excluded, and `#user_message` carries the bill metadata, one source text, the citation allow list and the news list, and nothing else.

## The citation warning does not block the operator's writes

The citation warning is advisory and does not block summary saves or draft approvals.

It lists every unverified section key. Saving does not clear it, because the citations were not checked again; hiding the warning would imply a fix that did not happen.

## Why the record of a run is kept at run time

A summary run stores the four prompt sections it sent, one row per bill in `bill_summary_prompt_snapshots`. The panel reads that row, so it can describe the run that wrote the summary rather than a run that has not happened.

The text lives in a table of its own rather than beside the summary in `bill_llm_provisioning`. That row is loaded and serialized on every render of the summary tab and again on each of the tab's five-second polls, while a single source text can reach the 300,000-character production cap — a column there would put a third of a megabyte through every poll to serve a modal nobody has opened. The snapshot's text is read only when a request asks for `summary_source_documents`, an optional prop the ordinary render never builds.

The row lands only where the summary it describes lands. `GenerateBillSummaryJob` captures the sections on the branch that actually calls the adapter, never on the branches that skip the call, and writes them after the persist guard reports `:persisted`. A run superseded by an operator's paste, or one whose provisioning row vanished mid-flight, therefore leaves no record behind. A snapshot write that fails is logged and dropped, because a paid call that landed must not be undone by bookkeeping.

Two other paths write a summary without a prompt of their own. A pasted summary read nothing at all, so `PasteSummaryService` deletes the row in the same lock that commits the paste. A batch answer did read a prompt, but `SummaryBatchItem` builds it at submit time and keeps nothing; the ingest can run a day later and has no way to say what was sent, and rebuilding the prompt then would record text the run never saw — so `SummaryBatchResultPersister` deletes the row too. Both leave the panel with no `read` half, which it reports as "not recorded" rather than filling in with a guess.

The row carries two kinds of thing. The four sections are the strings the run sent, byte for byte, because a modal showing anything else would be worse than showing nothing. Beside them sits `facts`, the same counts and dates the ledger renders, stored as JSON at run time so a source text since re-extracted cannot quietly change what the panel says a past run read. Those stored facts are read back through the same value object and the same alba resource the live counts go through, so `read` and `now` always carry the same keys — a snapshot missing a fact reads as a zero or a nil rather than as a missing key the page would render as nothing at all.

## Why the diff counts are attributed to a record

The Bill text row sizes the file the model read; the amended and referenced section counts sit under it, named as counts of the stored diff record. The two come from different stores, and they can disagree.

`BillSummaryPromptBuilder#source_text_section` sends the on-disk `.md` artifact and nothing else, while the section counts reach the ledger from `SummaryDiffFacts`, which parses the `diff_content` column on `bill_llm_provisioning`. Measured across the 204 development bills, 56 rows disagree with their file, and one bill's column reports twenty-two amended sections against a file carrying no diff at all.

A panel headed "What the model read" cannot put a count from one store into a sentence about text from the other. An operator opening the modal beside such a row would find the file contradicting the line above it, which is the exact confusion the panel exists to remove. So the row's own sentence carries only what the file yields — its kind and its length — and the counts move to a line naming the record they come from and pointing at the modal for the text. The staleness stamp follows the same rule: `diff_generated_at` dates that record, so the stamp reads "Diff record newer" rather than claiming the text is.

Attributing the counts does not close the split, it only stops the panel asserting it away. Closing it means one store producing both the counts and the text.

## Why each input opens a modal of its own

Every row carries a View control opening a modal of its own, holding that input's exact prompt text. Four inputs, four modals: an operator confirms one input at a time rather than reading one wall of prompt.

A row states a claim in counts, and the modal beside it is the evidence for that claim, so the two sit together and each modal is titled with its row's name. The tab already has a control that shows a whole prompt — Prepare prompt, in the empty state — and a whole prompt answers a different question: what would be sent if a run started now, rather than whether the law-code row's four keys are the four keys a run offered.

The text arrives as `summary_source_documents`, a prop the ordinary render leaves out and a modal asks for by name as it opens. Every open asks again rather than trusting what is already in props, since the tab's five-second poll and a write from another tab can both move the bill under a prop fetched minutes ago. While the request is in flight the modal says it is loading, and where the prop never arrives it says the text could not be loaded instead of showing an empty box.

The prop names where its text came from, and the modal repeats that rather than leaving the operator to assume. An origin of `run` is the stored row, byte for byte, and the modal dates it. An origin of `now` means no snapshot exists and the sections were rebuilt from the bill as it stands, which the modal says in a marked notice — a rebuilt section shown without that sentence is a claim about a run nobody recorded. A section the prompt never carried reads as one sentence, and a section that carried no text reads as another, because the snapshot stores an absent section as NULL and the two are different facts about the run: a llamacpp run has no news section at all, while an empty one would mean a search ran and returned nothing.

The text sits in a `<pre>` that scrolls inside the modal and carries `select-text`. Copying a passage out and checking it against the bill is the whole use of the modal, the same requirement that keeps the section titles out of Radix labels in [[bill-creator-summary-tab#Why the section titles are headings rather than labels]].

Nothing in the panel sets a stored section against a rebuilt one. Each prompt build mints a fresh sixteen-hex delimiter nonce, so the two never byte-equal even where their content is identical, and such a comparison would report a difference on every bill.

## Why the section titles are headings rather than labels

Each section title is a real heading rather than a Radix `Label`. The two that name a text area are tied to it with `aria-labelledby`; the third named nothing and is simply a heading.

Radix's Label cancels any mouse-down whose detail count is above one. That is deliberate upstream — it stops the browser selecting the label's own words when someone double-clicks to focus the field beneath it — but a title inside one can therefore never be selected by double-click at all. On this screen that cost is the point of the screen: an operator works a queue of bills by copying text out of it, and the words over each box are what they quote when they hand a bill to somebody else.

The primitive was not earning the cost either. Of the three sites, one carried no `htmlFor` and sat beside its control rather than around it, so it labelled nothing and existed only for its font weight. That one keeps no association, because there was never one to keep.

A real heading keeps the accessible name character for character — the same string, the same em dash — because the field points `aria-labelledby` at the heading's id, and it gives the tab a heading outline a screen-reader user can jump through, which a row of labels never did. The ids live in one small module rather than beside either component, since a heading and the field it names can sit in different components: the Public summary title is rendered by the editable-summary panel while the region that quotes it as its `aria-labelledby` is rendered by the completed view above.

## Why the run controls sit under the Public summary box

"Regenerate summary" and "Paste summary JSON" render directly under the Public summary box and its Save summary button, because the summary is what both of them replace.

Both act on the summary run. Regenerate posts to `regenerate_summary`, which writes `bill_llm_provisioning.llm_summary`; the paste dialog writes the same body by hand. Neither is an org-positions control. They previously rendered last in the completed view, below the draft positions list and immediately above the tab's Categories section, where an operator could reasonably read either one as acting on the positions beside them.

The run itself still produces both a summary and draft positions. Placement follows the text the operator is looking at when they decide to re-run, not the full set of rows the run touches.

### One action bar, one filled button

The summary panel offers a single row of controls, and Save summary is the only filled button in it; the model picker, Regenerate summary and Paste summary JSON are outlined, and the breakdown disclosure below them is quieter again.

The four controls used to sit in four separate rows in the same outline treatment, which left the publish action indistinguishable from the two controls that discard its subject. Further down the same column the Approve buttons on the draft position cards were filled, so the loudest thing on a screen about publishing a summary was a decision about an organization's stance, and the button that actually writes `bills.summary` looked like a secondary option. One filled button per section restores the ranking, and the vertical rule between Save summary and the run controls marks where "publish what is in the box" ends and "replace what is in the box" begins.

Below the `sm` breakpoint the bar stacks into full-width rows rather than wrapping. Each control already stands at the 44px touch floor, so a wrapped row of four reads on a phone as four undifferentiated bands of the same height with no ranking left in it — the stack at least keeps the order, and the filled Save summary keeps its rank at the top.

## Why a run with no breakdown says so

A run that produces no section breakdown displays a quiet explanatory note rather than an empty disclosure button or an invisible element.

The section breakdown is an optional field in the model's response schema. While the public summary is always present, some bills or runs omit a detailed section-by-section breakdown. Displaying an empty disclosure button would invite the operator to click only to reveal nothing, while omitting the element entirely leaves the operator wondering whether the breakdown failed to load. A plain text notice confirms that the run succeeded without generating a breakdown.

## Choosing the model for one regeneration

A picker beside the button that starts a run sends one of `AdminSetting.offered_models` with the request, and that model is used for that run alone.

`BillsController#summary_model_options` supplies the options array directly from `AdminSetting.offered_models`, resolving each human-readable title through `AdminSetting.offered_model_labels` and checking reasoning capability via `Llm::ModelCatalog.supports_reasoning?`, alongside `current_summarization_model` and `current_summarization_reasoning_effort`. Because administrators can add or remove structured-output OpenRouter models in `/admin/llm_settings`, the controller derives options dynamically from database state and cached catalog metadata rather than a static constant. The picker receives `{id: String, label: String, supports_reasoning: bool}` entries matching the exact models Sway currently offers.

The per-run model picker (`SummaryModelPicker`) renders these options via the searchable `Combobox` component, passing each model's identifier slug as search keywords (`keywords: option.id`). When the selected model supports reasoning, a reasoning level selector allows setting Default, Low, Medium, or High effort for that run, forwarded as `reasoning_effort` to `GenerateBillSummaryService` and `GenerateBillSummaryJob` (sending `"default"` when overriding a standing reasoning effort back to the model default for one run). When the selected model does not support reasoning or is unoffered, reasoning effort is omitted from the outbound request.

`AdminSetting.summarization_model` is a single standing default for every bill, changed at `admin/llm_settings`. An operator who wanted a stronger model for one difficult bill had to change that global setting, run, and change it back — a sequence that silently retunes every other summary generated in between.

The choice travels as an ordinary keyword argument rather than a new column. `GenerateBillSummaryService` checks it against `AdminSetting.offered_models` and hands it to `GenerateBillSummaryJob.perform_later`; ActiveJob serializes the argument, so a retry re-runs on the same model the operator picked. A column was rejected because nothing needs to read the choice back: `bill_llm_provisioning.llm_model` already records what the run actually used, which is what the provenance chip reports.

Both endpoints that start a run take the param through the same controller helper into that one service, so `generate_summary` and `regenerate_summary` apply the same check and refuse an unoffered model in the same words. An endpoint that ignored the param would have been the more confusing outcome: the picker sits on those branches too, and a choice the interface accepted and the server dropped is invisible.

The service is not the only gate. `Llm::RouteResolver.resolve` checks the per-run override against `AdminSetting.offered_models` again at perform time and falls back to the standing default (discarding any per-run `reasoning_effort` attached to a rejected override), because a queue entry written before the model list changed must not reach the adapter carrying an id Sway no longer offers. Standing `summarization_reasoning_effort` is inherited only when the resolved model matches the standing `summarization_model` and no per-run `"default"` override was requested.

The picker opens on the standing default rather than on nothing, so an ordinary Regenerate posts that model explicitly even when the operator touched nothing. The keyword is left off only where no model reached the request at all — a stored choice the server has stopped offering, or a page served without the options prop.

Those two paths part company once a job is on the queue. An explicit model is serialized with the enqueue, which pins the choice at the moment of the click and holds it through a retry. A run enqueued without the keyword reads `AdminSetting` at perform time instead, so an admin who changes the standing default between the enqueue and a retry moves that run onto the new model.

### Classification has its own model column

The model used to classify attachments is a second admin-tunable column rather
than a reuse of the summarization one.

It began as a pinned constant precisely so that an admin raising the
summarization model to the most expensive option could not silently multiply
classification cost several times over: classification is a bulk, low-judgment
call made over every candidate attachment, and the cheapest model is sized for
it. Reusing the one column would reopen exactly that. A second column keeps the
cost independence structural while still letting an operator tune it without a
deploy, which is where tunable settings belong. Its default is written as the
literal the constant carried rather than resolved through the supported-model
list, so the default cannot move when that list is reordered.

### The llamacpp provider ignores the choice

Direct Claude tier choices resolve to `llamacpp` locally when `llm_provider` is "llamacpp", whereas OpenRouter model choices resolve to OpenRouter in all environments via [[app/services/llm/route_resolver.rb#Llm#RouteResolver]].

Because `llamacpp` serves a single local model named by `Sway::Settings.llm.llamacpp_model`, picking between direct Claude models has no visible effect in development or test. The local engine responds with that single configured model regardless of which Claude tier was requested. In contrast, selecting an OpenRouter model sends the request to the upstream OpenRouter endpoint whenever credentials are configured, preserving distinct model execution across all environments.

### The choice is held above every control that starts a run

`BillCreatorLlmSummary` owns the selected model, not the picker's own component, because five controls start a summary run and each one belongs to a branch that renders instead of the others.

Regenerate summary sits in the completed view; Regenerate from latest data sits in the stale header above it; Generate summary and Retry belong to the branch that replaces the completed view when there is no draft; Start a new run belongs to an abandoned in-flight row; and a bill with no provisioning row at all has its own Generate summary in the empty state. Holding the choice one level above all of them means each run carries the operator's model without the value being threaded back up from whichever branch happens to be mounted.

Three of those controls once rendered no picker beside them, which put the gap on the branches an operator meets most often — a failed run, an abandoned one, a bill nobody has summarised. The choice was unreachable exactly where a second attempt on a stronger model is the obvious next move, and the run took the standing default with nothing on screen saying so. One picker component renders on each branch now; only one branch is mounted at a time, so its test id stays unique without any branch having to know about the others.

A model that is not among the options the server sent is sent as nothing at all. `AdminSetting` deliberately keeps working with a stored model that has since left `offered_models`, and sending that id back would have the service refuse a run the operator never configured. Sending nothing leaves the run on the standing default — which is that same stored model. Because an unoffered model resolves to nothing at request time, reasoning effort is also omitted so an unsupported parameter is never sent to the backend.

Because that stored model keeps working, both pickers have to say something for a value they cannot offer. The regeneration picker reads as the standing default. The settings field lists the retired model so the dropdown does not read empty, and disables it so the operator cannot re-pick a value the server would refuse.

### The confirm dialog names the model

The box that asks whether to throw the current summary away also says which model the new run uses.

It is the last screen before a request that costs money, and the picker that set the choice is not always in view behind it: the stale header's Regenerate sits well above the completed view's picker, and an operator returning to a tab left open has no other reminder of what they chose. A dialog that named only what the run destroys left the more expensive half of the decision unstated.

The line reads the label rather than the id, because the ids are dated API strings and the operator picked from a list of short names. A choice the server no longer offers reads as the standing default instead of as a raw id, which is what the run actually uses once the request drops that id.

### A new draft takes the place of the text in the box

When a regeneration this tab asked for lands, `LlmSummaryEditableSummary` mounts holding the new draft rather than the published summary.

The box is seeded from the published column on load and not from a draft already on the row, so an operator never mistakes stored draft text for what the public sees. A draft bought by a run the operator started seconds earlier is different: leaving the box on the old text would make the regenerate button look like it did nothing.

Telling those two apart cannot be done with React state. `BillCreatorLlmSummary` is keyed by `llm_generated_at`, so a landed run rebuilds the whole subtree instead of re-rendering it, and every piece of local state below the key is discarded exactly when the answer is needed. `summaryRunTabMemory` records the intent in `sessionStorage` instead: the generation stamp the tab was looking at when it asked. The draft claims the box only when a stamp is recorded *and* the row now carries a different one, and the record is consumed on use, so one request seeds the box once.

A request the server refuses gives the record back. Without that, a `Generation already in progress` refusal would leave the flag standing until some later run — a pipeline's, not the operator's — moved the stamp, and the box would seed from a draft nobody here reviewed.

`lastPublishedSummary` still tracks the published value even when the box was seeded from a draft. It is what the resync guard compares against to decide the server moved the summary underneath, and seeding it from the draft made that guard fire on the first render and overwrite the draft immediately.

The box is left alone once the operator has typed into it, and Save summary is still the only thing that writes the published column, so the published-versus-draft split the seeding rule protects is unchanged.

## A failed enqueue leaves a retry path

The generation action reports a failed queue write as an error the operator can retry, rather than saying that generation started.

[[app/controllers/bills_controller.rb#BillsController#generate_summary]] maps `:enqueue_failed` to a dedicated error message. [[app/services/generate_bill_summary_service.rb#GenerateBillSummaryService#call]] restores the row's retryable state before returning that outcome, so the next click is not blocked by a job that was never queued.

## Regeneration records its audit entry after enqueue

The regeneration audit entry is written only after the queue write succeeds, so it cannot record work that never started.

[[app/services/generate_bill_summary_service.rb#GenerateBillSummaryService#call]] owns that ordering. [[app/controllers/bills_controller.rb#BillsController#regenerate_summary]] opts into regeneration and maps the returned outcome; the audit entry belongs to the service operation rather than to the redirect.

## How summary-save errors reach the editor

When saving fails, the Summary tab shows the server's Inertia validation errors below the public summary field and keeps the entered text available for correction.

[[app/controllers/bills_controller.rb#BillsController#update]] returns model validation errors through the Inertia errors prop, and its `RecordInvalid` rescue returns the exception message as a base error. [[app/frontend/components/admin/creator/llm-summary/LlmSummaryEditableSummary.tsx#LlmSummaryEditableSummary]] reads that shared page prop and renders each field and message beside the editor; its failure toast directs the operator to those details.

### The click event is not a model or instruction

`useRegenerateSummary` ignores anything but a string in its model and instructions positions.

`SummaryRunButton` types its `onClick` as `() => void` while passing it to a DOM button, so a handler wired straight to `onClick` receives the click event and TypeScript reports nothing. Without runtime string guards, dialog or button confirm callbacks could forward synthetic mouse events as either model identifiers or per-run instructions.

## What the tab says about a run it did not finish

A status the operator reads has to be true of the row in front of them, which
is harder than it sounds because several different conditions all look like
"something is happening".

The stale chip names what actually overtook the summary. Testimony arriving on
its own is the one way a summary goes stale without the pipeline moving, so a
chip that always quoted the pipeline moment named the wrong cause and the wrong
time for exactly that case.

Every control that starts a run says "Queueing…", not "Generating…". The five
of them share the wording because they share the behaviour, and it is the
truer word: the request queues work that a background worker will generate.

A regeneration that stands down leaves the previous summary text in place, so
the tab keeps showing the ordinary editable view rather than the "generate
one" screen. The alternative offers to create something that already exists
and hides the text the operator might want to keep.

The badge reads the row's reclaimable flag as well as its status. Without it an
abandoned row stamped "Queued…" or "Generating…" directly above the notice
saying nothing was working on it.

A pipeline status the badge does not recognise draws a plain badge showing the
raw value. Drawing nothing left a blank space for the whole run, which reads as
a working screen with no status rather than as a status nobody has styled yet.

## Supplemental testimony is replaced, never appended

Saving supplemental testimony writes over what was stored rather than adding to
it, and clearing it is a separate explicit instruction.

An empty value must never wipe stored testimony, because the ordinary way to
arrive at an empty field is to load a page and not type in it. Clearing
therefore travels as its own flag, which no part of the interface used to send,
so only an API call could clear.

Both paths retract the evidence under every draft position drawn from that
testimony, which makes Approve refuse those drafts. Re-pasting the same text
does not undo the retraction, because nothing proves the new text is the old
text. That consequence is worth a warning, and for a long time only Clear
asked: an ordinary Save did the same replacement silently.

### The field is a sub-section, not a form row

Supplemental testimony renders on an inset panel under its own heading, inside
the testimony region rather than beside it.

It is the one place on the tab where an operator adds evidence by hand, and its
Save button is the only control in that region that writes, so it reads as a
step in the work rather than as a field appended to a list. Its title used to be
a form label in the same micro type the tab gave every other heading, which said
it was a field on a level with the textarea below it.

The inset treatment is written out rather than inherited from the nested-surface
rule in `application.css`. That rule de-emphasises a surface nested inside
another surface, and this panel's parent is an open region rather than a panel,
so the rule never fires on it. Written-out values chosen to match what the rule
produces mean the two agree if the panel is ever nested.

## A wholesale paste keeps the marks it never carried

A pasted draft-positions array replaces the stored one whole, and each internal mark on a stored entry is carried onto the pasted entry whose other fields match it exactly.

The operator's JSON never holds those marks. They record what the application
decided about a draft — that its evidence was retracted, that a person rewrote
its summary — rather than anything the model wrote, so a replace that took the
paste at face value would clear a decision that is still true and leave a draft
approvable that ought not to be.

## What the staleness marker quotes

The marker that says a summary has been overtaken names the moment and the reason that actually overtook it, rather than always naming the diff.

Testimony and diffs are separate columns and a hearings fetch on its own moves
only one of them, so a marker that could quote only the diff moment announced a
summary overtaken an hour ago by citing a pipeline run three weeks old. The
operator reading that has no way to tell a stale marker from stale work.

## Why the no-provisioning poll runs out

The tab refreshes itself every five seconds while it has reason to: a summary is being generated, a pipeline run for this bill is going, or the bill has no LLM provisioning row at all.

The first two conditions end on their own — a generation finishes, a run finishes — and the poll stops with them. Having no provisioning row is not an event that ends. It is a standing fact about a bill nobody has summarised yet, which is the ordinary state of a bill somebody has only just created. Left open-ended, such a bill polled every five seconds for as long as anyone left the tab open, with nothing running and nothing to wait for.

The branch is not redundant, so it was bounded rather than dropped. It exists so `LlmSummaryEmptyState`'s staleness guard learns that the pipeline moved underneath a prepared prompt, and neither of the other two triggers reaches that state: `isGenerating` needs a provisioning row to read a status from, and the ActionCable subscription only follows a run that was already active when the tab mounted. The sibling Pipeline tab polls on run status alone, which is self-terminating, but only one tab is mounted at a time, so it covers nothing while an operator is reading this one.

The bound is twelve attempts — one minute — held per bill, so picking a different unsummarised bill starts a fresh watch. A change is most likely just after the operator arrives or acts, and after a minute of an idle tab showing an unsummarised bill, a reload is what learns anything new. Should a run or a generation start inside that minute, one of the two self-terminating conditions takes over and the poll continues for as long as that work does.

The pipeline-run condition is there for a message that never arrives. Once a run ends, its summary is neither generating nor missing, so without that condition the tab would be betting on one ActionCable message landing. `usePipelineRunSubscription`'s catch-up reload fires only after a disconnection long enough to raise the paused banner, and swapping tabs on this screen is not that kind of disconnection — a message missed during a tab change is missed for good, leaving a notice about work that had already finished with nothing but a manual reload to clear it. `spec/system/admin_pipeline_run_finish_spec.rb` reproduces it by finishing a run without sending the message.

## Which screen a failed run leaves behind

The tab shows the summary it has, or offers to make one. That choice reads the summary alone: a row carrying summary text opens the Public summary panel, and a row carrying none opens the generate branch, whatever draft positions the bill holds.

It used to read both. A failed row with no summary but with draft positions was routed to the Public summary panel, which meant an empty summary box under a Failed badge — a screen that existed only so the drafts underneath it would render. With the drafts on their own tab there is nothing underneath, so the routing had nothing left to buy and cost the operator the two things the generate branch gives them: the reason the run failed, and a Retry beside it.

Reading the positions count also made the summary tab's shape depend on advocacy material, which is the coupling the tab split exists to break. A reader who sees the screen change when an organization's position is drafted has been told something untrue about what a summary is made from.

## Why the summary tab's in-flight notice says nothing about positions

While a run is queued or writing, the summary tab shows one notice about the summary alone: which draft is on screen, what the run will do to it, and that the published summary in the box below is untouched. Draft positions are not its subject.

The two tabs once shared one notice, which had to speak for both halves of a run and named draft positions on a screen that no longer shows any. On the summary tab that reads as the model weighing organization positions while it writes — the belief this tab's ledger exists to correct, since testimony and positions never reach the summary prompt at all. The positions half of the sentence moved to the Positions tab's own notice, which is where Approve is switched off and where the reader can see the drafts being described, in [[bill-creator-positions-tab#Why Approve says on this tab why it is off]].

Both notices carry the same element id, since only one of them is ever mounted: the tabs are exclusive, so a control on either tab can point at "the notice" without knowing which tab it is on.

## Why the poller is a mounted component

The five-second refresh is a component with no props: `SummaryGenerationPoller` calls `usePoll` and renders nothing. Mounting it starts the poll, unmounting it stops it, and the conditions deciding whether it is on the page are the whole switch.

It replaced an effect that called a start or a stop as a flag changed. An effect's work is to bring React level with something outside it, and there is nothing outside here: React already mounts and unmounts the element, and `usePoll` already cleans up after itself as it goes.

The component takes `Record<string, never>` deliberately. `usePoll` reads its interval and its prop list on first render and never again, so a poller handed new arguments through props would go on asking for the old ones. A poller that has to change either would need a `key` derived from that value, so a change remounts it rather than re-rendering it.

The flags deciding whether it is mounted are worked out during render from the props themselves, with no stored state. A polled reload lands carrying `generation_status` at completed or failed, `isGenerating` reads false on the next render, and the poller unmounts itself. The same fact held in state would need an effect of its own to clear it, and would be wrong for as long as that effect lagged.

## Why the summary card is keyed on the generation time

`BillCreatorLlmSummary` carries a React key of `llm_generated_at`, or `none` where no summary exists yet, so a paste-back or a regenerate that saves a new summary rebuilds the card instead of leaving an earlier draft in it.

The key is deliberately not how the two text boxes under it stay current. Nothing stamps `llm_generated_at` when `bills.summary` is written, so a save from the Creator tab moves the summary without moving the key. Each box follows its own server value during render instead, guarded so a background refresh cannot overwrite a half-typed edit.

## Why the organizations panel carries a remount key

Both places that render the organizations panel key it on the bill id and the sorted ids of the bill's saved organizations, so an update that changes that set rebuilds the panel rather than re-rendering it.

The panel holds its own `useForm`, seeded from `bill.organizations` at mount, and Inertia form state does not follow changed initial values. The tab's five-second poll and its pipeline subscription both ask for `bill` back, and approving a draft position posts and returns a fresh `bill`; with no key on the panel, none of those reached the rows the operator was reading, and an organization added or removed on the server stayed off the list until a full navigation. `BillCreatorLlmSummary` is keyed on `llm_generated_at` for the same reason.

The key names the organization set rather than the bill's `updated_at`, because the panel also carries summary text an operator has typed and not yet saved. A stamp that changed on every write would discard that text on each poll tick, while the id set changes only when the server's list of organizations on this bill is a different one. An edit to an organization already in the set — an inline rename, for one — leaves the key alone, which is why the rename path writes the new label into the form data itself.

The bill id is part of the key because the form posts the `bill_id` it was seeded with. Two bills carrying the same organizations would otherwise share a key, and the panel would submit the earlier bill's id.

The removed-row draft cache lives above this keyed form in both [[app/frontend/components/admin/creator/BillCreatorAccordions.tsx#BillCreatorAccordions]] and [[app/frontend/components/admin/creator/BillCreatorPositions.tsx#BillCreatorPositions]]. That lets a server response change the organization-set key and reseed saved rows without discarding an unsaved position that the operator can add back; [[bill-creator-organization-form#The cache outlives the organization-set form]] owns the cache lifetime.

## The LLM Summary accordion points to summary review

The accordion's summary panel is a placeholder because summary review happens on the dedicated Summary tab.

[[app/frontend/components/admin/creator/BillCreatorAccordions.tsx#BillCreatorAccordions]] leaves the summary copy in the accordion and directs operators to the Summary tab for the LLM summary and news articles.

## Operator instructions for one regeneration

An optional text field in the confirmation dialog lets an operator provide per-run guidance for a summary regeneration without modifying standing system prompts or persisting instructions across runs.

The instructions travel as a per-run `summary_instructions` parameter alongside the chosen summarization model. The Rails controller and service trim surrounding ASCII whitespace and enforce a limit of 2,000 Unicode code points (with astral character parity). Input exceeding this limit or non-string values are rejected with an Inertia redirect error before enqueuing work.

Operator instructions remain strictly subordinate to factual source grounding, neutrality rules, and output schemas. Guidance can steer emphasis toward specific topics—such as requesting a missing property tax rate or fiscal impact focus—but cannot invent facts, override legislative bill text, or alter structured JSON schemas. All factual claims must originate from the authoritative bill and law sources provided in the prompt. Positions prompts and non-summary LLM calls never receive operator guidance.

### Validation and code point limits

The 2,000 Unicode code point ceiling uses code point length rather than UTF-16 code units so that astral characters count as single characters.

Both Ruby and TypeScript count code points identically after stripping surrounding ASCII whitespace (`[\x20\t\r\n\f\v]`). In Ruby, `String#length` returns code points; in JavaScript, `Array.from(str).length` avoids UTF-16 surrogate pair miscounts that `string.length` would produce. Non-string inputs or values exceeding 2,000 code points are rejected before changing provisioning status, writing log entries, or enqueuing background jobs.

### Non-ASCII whitespace preservation

ActiveSupport blankness helpers are bypassed during normalization so that non-ASCII whitespace such as non-breaking spaces remains intact.

ActiveSupport defines `.blank?` to treat all Unicode whitespace—including non-breaking spaces (`U+00A0`)—as blank, causing `.presence` to return `nil`. In contrast, the operator interface treats `U+00A0` as an intentional character, counts it as one code point, and trims only surrounding ASCII whitespace characters (`[\x20\t\r\n\f\v]`). If the backend relied on ActiveSupport's `.blank?` or `.presence`, an input containing `U+00A0` would be dropped silently as omitted. Using explicit `empty?` checks after ASCII-only trimming guarantees exact parity between frontend validation and backend ingestion, preventing unexpected data omission.

### Separation from system prompts and evidence enclosures

Operator instructions are placed exclusively inside `user_message` under a dedicated operator-guidance header and never inside `system_prompt`.

Excluding operator guidance from `system_prompt` preserves prompt prefix caching across requests. Modern inference providers cache static system prompt prefixes, reducing latency and operational inference costs; injecting per-run operator text into the system prompt would invalidate the cache on every instructed regeneration. Within `user_message`, instructions sit under a distinct `## Operator guidance` header placed completely outside source delimiters, preventing prompt-injection ambiguity between source evidence and operator direction. The model is explicitly informed that operator guidance cannot supply missing facts or contradict source materials.

### Lifecycle and run isolation

Instructions exist ephemerally for the immediate regeneration request and transient job retries, without long-term database persistence.

Passing `summary_instructions` as an ActiveJob keyword argument allows serialization and retry survival across transient network errors without adding a database column. Storing instructions in the database was rejected because no interface reads past instructions back, and persistent storage risks accidentally applying previous instructions to subsequent uninstructed runs or other bills. Similarly, `bill_summary_prompt_snapshots` records only the four authoritative source sections and facts, never operator instructions.

### The regeneration confirmation dialog and draft lifecycle

The confirmation modal holds an optional multiline instructions field that captures operator guidance and resets cleanly across bill navigations.

Confirmation modal instances in [[app/frontend/components/admin/creator/llm-summary/LlmSummaryCompletedView.tsx]] and [[app/frontend/components/admin/creator/llm-summary/LlmSummaryStatusShell.tsx]] mount [[app/frontend/components/admin/creator/llm-summary/LlmSummaryRegenerateConfirmDialog.tsx]], which renders an accessible multiline textarea paired with a label. First-generation and abandoned-run controls do not mount this dialog and remain uninstructed. The input field displays a property tax rate placeholder and helper text explaining that instructions apply solely to the immediate run and must be supported by source material.

Astral-aware length calculation (`Array.from(trimmed).length`) enforces parity with the backend 2,000 code point limit after stripping surrounding ASCII whitespace (`[\x20\t\r\n\f\v]`), while preserving internal newlines and non-ASCII whitespace. Over-limit inputs trigger an actionable error alert without silent clipping and disable the confirm button.

Submission passes through [[app/frontend/components/admin/creator/llm-summary/useRegenerateSummary.ts]], which delivers `summary_instructions` alongside `summarization_model` to `/bills/:id/regenerate_summary` using Inertia's `router.post`. Blank or whitespace-only inputs omit the parameter entirely.

Draft text follows an ephemeral in-memory lifecycle. It is preserved during same-bill polling rerenders and retained after server refusal or transport failure (`onNetworkError`), allowing an operator to retry without retyping. Erasing the input and confirming explicitly commits the blank state so subsequent refusals retain blankness. In contrast, unsubmitted drafts are discarded on dialog cancellation, Escape keypress, outside click, component unmount, or navigating across bills, and cleared immediately upon verified accepted enqueue. Instructions are never persisted to `localStorage`, `sessionStorage`, or `summaryRunTabMemory`.
