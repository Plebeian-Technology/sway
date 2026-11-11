---
lat:
  mode: explanation
---

# The approval guard chain

`ApproveOrgPositionService#call` is the only path that turns a draft into a PUBLIC `OrganizationBillPosition` (`active: true`, asserting a named organization's stance on a bill).

`ReplaceBillOrgPositionsService` and `OrganizationBillPositionsController` also write that table, but from an admin-supplied `organization_id`, never from `draft_org_positions` — they carry no draft that could have been retracted. Every check in this document exists because this class is that one choke point.

## Why this class exists separately from the controller

`ApproveOrgPositionService` moved out of `BillsController#approve_org_position` so the controller stays thin.

The service owns the business logic: validate the inputs, fuzzy-match (or create) the organization, create-or-update ("upsert") its `OrganizationBillPosition`, remove the approved draft from the provisioning draft list, and write the `org_position_decision` audit entry. The controller maps the returned Symbol to a redirect — see [[docs/reference/approve-org-position-outcomes.md|ApproveOrgPositionService outcomes]].

## Why summary validation runs first

The edit endpoint and the card's own editor both allow a blank summary on purpose — an operator may clear the text while still drafting it.

Approve is different: it calls `#upsert_position`, whose `save!` runs the model's `summary` presence validation. Left unguarded, a blank summary raised an unrescued `RecordInvalid` and answered the click with a 500 instead of a message the operator could act on. The model validation stays as it is; `:summary_required` only turns that raise into a refusal, the same way the `org_name` check above it already does.

This check runs BEFORE the evidence checks below, so a blank summary on a retracted or testimony-less draft reports `:summary_required` first, not the evidence refusal. That changes which message the operator sees, not which draft gets approved.

## The hole: a dropped :index skipped everything

Every check below `:draft_index_required` begins `return false if @index.blank?`.

That's correct for a caller asserting a position from its own inputs. But a caller that sends `draft_token` or `draft_org_name` and NO `:index` is not such a caller — it's saying "promote THIS draft." Before `:draft_index_required` existed, sending that and no `:index` made all four checks below skip, `#delete_approved_draft` return early, and the request publish an active `OrganizationBillPosition` with no evidence checked at all — while the draft it named stayed on screen, ready to be approved a second time.

Everything else in this class fails closed: `#draft_at` refuses a negative index, an unresolvable index refuses the publish, a missing provisioning row counts as missing testimony, `#delete_approved_draft` raises rather than skipping. `:draft_index_required` closes the one place that failed open — the outermost control, reachable from the same URL the draft card posts to. See [[docs/explanation/org-position-draft-identity-exemption.md|Draft identity and the approval exemption]] for the outcome itself.

## The pre-check / re-check split

Every guard below runs twice.

Every guard below runs twice: once before the transaction opens (a pre-check that takes no write lock and leaves the org, position, and draft list untouched in the common case), and once again inside `#delete_approved_draft` while the provisioning row is locked (the authoritative re-check). The second run is what actually decides; the first exists only to leave a fast, lock-free path for the case that fails.

### draft_index_mismatch?

Drafts are addressed by array position, and positions shift whenever any draft is deleted (`BillDraftOrgPositionsController#update` notes the same hazard).

Without a re-check, a stale or filtered index could silently delete a DIFFERENT pending draft, with the audit entry naming the wrong organization.

### evidence_retracted

Refuses a draft whose evidence `FetchHearingsService` has since withdrawn.

`fetch-hearings` runs on its own schedule, so it can land a retraction between the pre-check's read and the write; without the re-check that approval would publish an org's stance on evidence the system had already withdrawn. `#draft_evidence_retracted?` (the private method behind both checks) works from the same `#draft_at` resolution as the identity checks, and reads the mark documented in [[docs/explanation/evidence-retraction.md|Marking a draft's evidence as retracted]]. The mark is per-entry: an unmarked sibling of a marked draft is still approvable.

### bill_testimony_missing?

See [[docs/explanation/org-position-bill-testimony-check.md|The bill-level testimony check]].

### run_in_flight?

A queued or running summary job replaces `draft_org_positions` WHOLESALE, so a draft it's about to overwrite must not become a public position first.

The card greys the Approve button out on the same fact; this check is the half a stale tab cannot skip.

It needs both halves for the same reason every other rule here does. The window is a poll interval, not an instant: two admins work the same locale, one clicks Regenerate, and the other's page learns about it up to five seconds later — longer if the tab was in the background when the run started. Inside that window the other admin's Approve could publish the position and delete the draft, and the run then replaces the whole list, so nothing on the row or the screen connects the published position to the draft that was discarded. That's the outcome an earlier fix was made to prevent, reached through a narrower door.

BOTH `pending` and `generating` are checked, not only `generating`. The row is armed at `pending` and the drafts are replaced whenever the positions call comes back, so a run that hasn't started yet is exactly as much of a reason to wait. `BillCreatorLlmSummaryStatus` derives its `runInFlight` from both statuses; fixing only one arm of a two-arm guard is a recurring defect shape in this codebase.

### Frontend prop notes

`LlmSummaryCompletedView`'s `runInFlight` prop gates the DRAFT CARDS, not the run-buying buttons (`isRegenerating`).

Approve publishes a public position — whether that's allowed is a fact about the row, not who clicked what.

`runInFlight` reaches `LlmSummaryOrgPositions`'s cards too: Approve creates a PUBLIC position and used to stay clickable on a queued/running row. The server now refuses `:run_in_flight` too.

A missing provisioning row is NOT in flight: there's no run and no draft, and `bill_testimony_missing?` has already refused such a caller.

## The lock that makes the re-check authoritative

`#delete_approved_draft` reads, edits, and writes back the WHOLE `draft_org_positions` array while the row is locked.

An earlier version checked identity before the transaction opened and then wrote back an array it had read with no lock at all, so a reject or an edit landing in that window was overwritten without a trace — the very data the guard exists to protect, lost.

`with_lock` reloads the row inside the transaction, and `config/database.yml` sets `default_transaction_mode: IMMEDIATE`, so SQLite takes the write lock the moment the transaction begins: no other connection can commit between the re-read and the write. The re-checks and the delete leave no gap for anyone else to slip into.

Each re-check must bail by RAISING, never by `next`. The bounds test was once `next unless idx < drafts.length`, which left the block before the raises and let the enclosing transaction commit the org and the public position `#call` had already upserted. A bail here is a refusal to publish, not a decision to skip the delete, so it has to unwind the whole chain — the org, the position, and the decision log all roll back together.

## Why approval used to leave a stale draft and no audit entry (UAT Test 5)

The controller used to create the `OrganizationBillPosition` row but leave the draft behind in `bill_llm_provisioning.draft_org_positions`, so the card never disappeared from the screen after Approve.

It also wrote no `org_position_decision` audit entry: "rejected" and "edited" were logged by the sibling `BillDraftOrgPositionsController#update` endpoint, and "approved" had nowhere to go. Both are fixed by `ApproveOrgPositionService` owning both the draft removal (`#delete_approved_draft`) and the audit write (`#log_decision`) as part of the same outer transaction described below.

## Why call wraps the whole write chain in one outer transaction

`#call` wraps `find_or_create_org`, `upsert_position`, `delete_approved_draft`, and `log_decision` in one `ActiveRecord::Base.transaction`, on top of the inner lock-and-recheck transaction `#delete_approved_draft` opens itself.

A failure partway through this outer chain — say, `log_decision` raising after the position was already upserted — rolls back a freshly-created `Organization` instead of orphaning it in the database with nothing pointing at it. The audit log's `after_commit` broadcast (`PipelineActivityLogEntry`) waits for THIS outer commit specifically, so a subscriber to that broadcast never sees an approval that did not actually persist.

When one of the re-check exceptions (`DraftIdentityMismatch`/`EvidenceRetracted`/`NoTestimony`/`RunInFlight`) is caught by `#call`'s own `rescue` clauses, the transaction above has already rolled back by the time the rescue runs — so a freshly-created `Organization` and the position `#call` had already upserted are both gone, landing on the exact same "nothing was touched" outcome the pre-check produces when it catches the same condition before any write happens at all.

## Why draft_evidence_retracted? returns false, not the retraction, for a nil entry

`#draft_evidence_retracted?` returns `false` when `#draft_at` cannot resolve an entry (`entry.nil?`), rather than treating a missing entry as a retraction.

An index that points at no entry at all is `#draft_index_mismatch?`'s refusal to make, not this one's — that check runs FIRST on both the quick path and the locked path, and "the list has changed, look again" is an answer the caller can actually act on. Answering `:evidence_retracted` here instead would claim a retraction that never happened. Returning `false` lets nothing slip through: the other check has already stopped an unresolvable index, and the shared `#draft_at` helper is what keeps that guarantee true for every caller.

## Why a missing provisioning row raises rather than returning inside the lock

`#delete_approved_draft` raises `DraftIdentityMismatch` when `@bill.bill_llm_provisioning` is nil, rather than returning quietly.

A bill with no provisioning row has no draft to approve at all, and `#call` has already refused such a bill as `:no_testimony` earlier in the chain (a missing provisioning row counts as missing testimony) — so reaching this point with a nil provisioning row should be unreachable. Raising instead of returning means this can never quietly become a silent publish if that earlier ordering ever changes; a `return` here would let the org and position `#call` already upserted commit with no draft ever having been checked.

## Why the deleted index is re-derived rather than captured before the lock

The line that deletes the approved entry from `draft_org_positions` calls `draft_index` again inside the lock, rather than reusing a value read before `with_lock` was taken.

`#draft_index_mismatch?` above has already raised unless `#draft_at` resolved, so by this point the index is known to be in range and non-negative — but it is re-derived from the one parser rather than a locally captured value, so the value that was bounds-checked is guaranteed to be the exact value that gets deleted. `draft_index || raise(DraftIdentityMismatch)` re-asserts rather than defaults on this path too: an unresolvable index here must refuse the publish, never silently fall back to deleting slot 0.

## Acknowledging testimony coverage gaps

[[app/services/acknowledge_testimony_coverage_service.rb#AcknowledgeTestimonyCoverageService]] records an operator's review of a bill's testimony coverage gaps before [[app/services/approve_org_position_service.rb#ApproveOrgPositionService]] permits testimony-sourced draft approvals.

Each acknowledgement row in [[app/models/testimony_coverage_acknowledgement.rb#TestimonyCoverageAcknowledgement]] pairs the bill with the digest of [[app/services/testimony/coverage_report.rb#CoverageReport]]. If the caller's submitted digest differs from the live report's digest, the service returns `:digest_mismatch` rather than recording an acknowledgement against coverage numbers that moved underneath the operator.

When two requests acknowledge the same `[bill_id, coverage_digest]` pair concurrently, rescuing `ActiveRecord::RecordNotUnique` and returning the existing row treats the race as idempotent success. Inside [[app/services/approve_org_position_service.rb#ApproveOrgPositionService#coverage_not_acknowledged?]], the sixth guard re-evaluates [[app/services/testimony/coverage_report.rb#CoverageReport]] under `provisioning.with_lock` for testimony-sourced callers (while exempting news-sourced drafts that carry a `bill_news_article_id`), ensuring a concurrent testimony update invalidates a stale acknowledgement before any position is published.
