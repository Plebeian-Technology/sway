---
mode: explanation
summary: "Explains PasteSummaryService's overall contract and why each field in the attrs hash it builds (generation_error, llm_generated_at, llm_provider, llm_model, summary_run_id, the citation re-check) is set the way it is."
status: agent-extracted
related: [paste-summary-audit-transaction-boundaries, paste-summary-status-reuse-and-pending-bug, run-marker-column-semantics, citation-validator-design, bill-summary-ai-unreviewed-detection]
---

# What `PasteSummaryService` owns, and why its `attrs` hash is built this way

`PasteSummaryService` takes a bill summary that an operator pasted in as
JSON and saves it. This class does the thinking: read the JSON, check it
has the right shape (`BILL_SUMMARY_SCHEMA`), save what passes onto
`bill.bill_llm_provisioning`, and record a `paste_summary_accepted` or
`paste_summary_rejected` entry in the audit log. Everything about the web
response — the 200 or 422, the extra payload the mobile app needs — stays
in the controller, which translates the result below.

## What `#call` returns

Two things: an outcome and a list of errors. The outcome is `:persisted`,
`:persisted_unsettled`, `:invalid_json`, or `:schema_invalid`. Each error
is a hash with a path and a message; the list is empty when the paste
succeeded. The controller hands that list straight to
`render_paste_summary_errors`.

`:persisted_unsettled` is a SUCCESS with one thing left undone: the body
and its audit entry are committed, but the status could not be moved and
nothing else will move it. The operator has to be told, because the
screen will draw the old status over their new text.

## Why `generation_error` is cleared on every paste

TWO places write the summary body: this service and
`GenerateBillSummaryJob`. The job clears `generation_error` before it
starts and counts on that — it assumes any error text on a finished row
came from its own positions step. `GenerateBillSummaryService` writes no
summary body at all; it clears `generation_error` and enqueues the job.

The bug that made this matter: a run asks the model for organization
positions, gets rate-limited (HTTP 429), and finishes with the error
"positions call failed (the summary is valid): ...". The UI then shows
"Draft org positions were not generated". An operator pastes a
replacement summary that DOES include `draft_org_positions`, and that
warning kept showing above the pasted cards. A paste replaces the body
the error was about, so the error goes with it.

## The `attrs` hash: one field at a time

`draft_org_positions` arrives as the column's own element type, which is
deserialized JSON — an element is not guaranteed to be a `Hash`, hence the
wide `@type var attrs:` declaration on the hash local.

- **`llm_generated_at`** is set on every paste. The frontend watches
  `llm_generated_at` to know it should rebuild `BillCreatorLlmSummary`.
  `llm_generated_at` doubles as the React key `BillCreatorLlmSummary`
  remounts on: that component keeps `editableSummary` in local state and
  deliberately does not re-sync from the bill prop, so a changed key is
  what refreshes it after a paste. This is tested at the request level
  (UAT Test 4) because the front-end remount behavior hangs off this
  database write. A second paste must move `llm_generated_at` forward
  even when the pasted body barely changed; the request spec covering
  this uses `travel_to(1.minute.from_now)` rather than a real `sleep
  0.01`, which was a timing dependency in a suite that already contends
  on one shared test database and said nothing about intent — a full
  minute makes the two writes plainly different moments regardless of
  how fast or slow the two requests actually run.
- **`llm_provider`** is set to `BillLlmProvisioning::OPERATOR_PASTE_PROVIDER`
  — the constant, not the word typed out again. `Bill#summary_ai_unreviewed?`
  reads it to keep the "written by AI, unreviewed" notice off a pasted
  body (see
  [bill-summary-ai-unreviewed-detection.md](bill-summary-ai-unreviewed-detection.md)),
  and a second hand-typed copy is how the two stop matching.
- **`llm_model`** is explicitly CLEARED, because no model wrote this
  text. `llm_provider` and `llm_model` travel together — `to_builder`
  shows them side by side — so pasting over a row that had finished on
  `claude-sonnet-4-6` used to read "operator_paste / claude-sonnet-4-6",
  crediting hand-written text to a model that never saw it.
- **`summary_run_id`** is set to a fresh `SummaryRunMarker.operator_paste`
  value — a flag that tells any queued or retrying
  `GenerateBillSummaryJob` "an operator paste owns this text now — leave
  it alone" (see
  [run-marker-column-semantics.md](run-marker-column-semantics.md)). It
  is saved in the SAME database update as the text it describes, so the
  two can never come apart: there is no moment where the paste exists
  without the flag. That stops a queued job from paying for a fresh
  summary and overwriting the paste, in every state, not only mid-retry.

## Why citations are re-checked on every paste

The warning banner reads `citations_valid` and `invalid_citations`
straight off this row, so skipping the re-check would make the paste
inherit the PREVIOUS summary's verdict.

The judgement itself lives in `SummaryCitationValidator.verdict_attrs`
(see [citation-validator-design.md](citation-validator-design.md)) so that
this service and `GenerateBillSummaryJob` cannot disagree. They once did:
given a body with no cited sections, one recorded "not checked" (`nil`)
and the other recorded "clean" (`true`), each with its own passing test.

## `#settle_pasted_row!`: why the deferred-settle log message names the re-read

When the row is left in flight (`pending` or `generating`), the service
logs it rather than staying quiet. The operator pasted something and the
Bill Creator will keep showing "still running", so the reason has to be
findable somewhere.

This message used to say the flag "stops that job re-buying over the
pasted body". That was true for a queued job but false for one already
running: a running job checked the flag once, near the start, before this
paste existed, so it went on to overwrite both the text and the flag. The
reassuring log line printed at the exact moment the work was destroyed.
It is true for both cases now only because `GenerateBillSummaryJob`
re-reads the flag under the row lock at both points where it saves. The
message names that re-read on purpose, so it stops being true if the
re-read is ever removed.

