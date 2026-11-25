---
lat:
  mode: reference
---

# News organization position persistence

Persistence pipelines filter draft organization positions against source article snapshots before persisting to database columns, guaranteeing zero ungrounded entries and zero unreviewed organization entity creation.

## Position origin and affiliation

Each organization position records who wrote it in `source_kind` and where it came from in `source_url`, both nullable columns on [[app/models/organization_bill_position.rb#OrganizationBillPosition]].

### Values and write paths

Every write path sets both columns for what it wrote, so the latest write decides the origin. The two admin save paths set `sway_admin` only on a new position or one whose support or summary changed; an unchanged re-save keeps its origin.

| `source_kind` | Who wrote the position | Write paths | `source_url` |
| --- | --- | --- | --- |
| `hearing_testimony` | Sway, from hearing testimony | [[app/services/approve_org_position_service.rb#ApproveOrgPositionService]] approving a testimony draft or a claimed affiliation | Always nil: testimony attachment entries carry no public URL for a letter |
| `news_article` | Sway, from a news article | [[app/services/approve_org_position_service.rb#ApproveOrgPositionService]] approving a news-sourced draft | The draft's `source_url` |
| `sway_admin` | A Sway admin, by hand | [[app/controllers/organizations_controller.rb#OrganizationsController]] `#create`, [[app/services/replace_bill_org_positions_service.rb#ReplaceBillOrgPositionsService]], and an approval that names no draft | Nil |
| `organization` | The organization's own members | [[app/services/approve_position_change_service.rb#ApprovePositionChangeService]] approving a member's change; the development seeds | Nil |
| nil | Sway, origin not recorded | Positions written before the columns existed and not matched by the backfill | Nil |

### Existing positions

A nil `source_kind` reads as compiled by Sway. The backfill sets `organization` only where an approved member change was the latest write: updated no earlier than five seconds before the position.

### Payloads

Both public position payloads send `source_kind` and `source_url`, null when unknown: `to_public_json` on [[app/models/organization_bill_position.rb#OrganizationBillPosition]] and [[app/serializers/bill_page_organization_bill_position_resource.rb#BillPageOrganizationBillPositionResource]]. The membership page props from [[app/controllers/organizations/base_controller.rb#BaseController#membership_as_props]] send `source_kind` and `source_url` too.

## Persistence callers

Four domain execution callers invoke draft position persistence and grounding filters.

| Caller | Source Snapshots | Filter Method | Destination |
| --- | --- | --- | --- |
| [[app/jobs/generate_bill_summary_job.rb#GenerateBillSummaryJob]] | `for_summary` (reporting) and `for_testimony` (commentary) | `NewsOrgPositionGroundingService.filter_draft_positions` | `BillLlmProvisioning#draft_org_positions` |
| [[app/services/summary_batch_item.rb#SummaryBatchItem]] | Captures `for_summary` for reporting and `for_testimony` for commentary | Prompt enclosure formatting | Claude Batch API Item |
| [[app/services/summary_batch_result_persister.rb#SummaryBatchResultPersister]] | `for_summary` and `for_testimony` resolved via run receipts | `NewsOrgPositionGroundingService.filter_draft_positions` | `BillLlmProvisioning#draft_org_positions` |
| [[app/services/paste_summary_service.rb#PasteSummaryService]] | Most recent `for_summary` and `for_testimony` snapshots | `NewsOrgPositionGroundingService.filter_draft_positions` | `BillLlmProvisioning#draft_org_positions` |

## Snapshot resolution matrix

Snapshot resolution maps caller answer types and receipts to the appropriate purpose scope.

| Answer Type | Primary Scope | Secondary Scope |
| --- | --- | --- |
| `SUMMARY` | `for_summary` (`purpose: "summary"`) | None |
| `POSITIONS` | `for_testimony` (`purpose: "testimony"`) | `for_summary` (`purpose: "summary"`) |

## Zero entity creation invariant

Draft position persistence paths strictly update the JSON array on [[app/models/bill_llm_provisioning.rb|BillLlmProvisioning]] and never instantiate or persist public records.

- `Organization` count remains invariant across all summary and positions generation runs.
- `OrganizationBillPosition` count remains invariant until explicit administrator approval.
- User-managed organizations with user memberships are excluded from drafts.

## Approval of news-sourced draft positions

News-sourced draft positions bypass hearing testimony existence checks and require grounded evidence verification alongside user membership safeguards prior to approval.

| Guard | Rule | Failure Outcome |
| --- | --- | --- |
| Testimony Bypass | News-sourced drafts (`bill_news_article_id` present) skip `BillLlmProvisioning#testimony_present?` check. | N/A |
| Grounding Check | Backing news article must remain approved and match `text_version_id` via `NewsOrgPositionGroundingService.entry_still_grounded?`. | `:evidence_retracted` |
| Membership Check | Target organization must have zero `UserOrganizationMembership` rows. | `:organization_has_users` |
| Deduplication | Matching against existing organizations uses normalized exact match followed by Jaro-Winkler distance threshold (0.90). | N/A |
| AI Summary | Sets `ai_summary: nil` on [[app/models/organization_bill_position.rb#OrganizationBillPosition]] since news-sourced positions quote article text verbatim. | N/A |
