---
mode: reference
summary: "Catalog of the TRefusalKey error keys notifyServerRefusal reads, which controller and service sends each one, and why they are a fixed union rather than a plain string."
status: agent-extracted
related: [docs/explanation/notify-server-refusal-pattern.md]
---
<!-- vale Vale.Spelling = NO -->

# `TRefusalKey` catalog

`TRefusalKey`
(`app/frontend/components/admin/creator/notifyServerRefusal.ts`) is the
fixed set of `errors` keys the controllers behind the Bill Creator screen
actually send to `notifyServerRefusal`.

| Key | Source | Sent for |
| --- | --- | --- |
| `org_position` | `ApproveOrgPositionService` | Missing org name, invalid stance, stale position number, retracted evidence, no testimony left, or a run already in flight (`:run_in_flight`). Reject also reports its own position-number mismatch under this key. |
| `generation` | `GenerateBillSummaryService` | No pipeline data, a generation already running, or a failed queue write after arming (`:enqueue_failed`). Used by the generate and regenerate_summary actions. |
| `legislator_votes` | `LegislatorVotesController#create` | A vote that failed to save for one legislator, plus its catch-all rescue message. |
| `pipeline` | `PipelineRunsController#force_fail` (run not in flight, or wrong confirmation phrase) and `BillsController` (resume/stage not allowed) | Resume, restart, and run-all actions. |
| `testimony_coverage` | `AcknowledgeTestimonyCoverageService` | Nothing left to acknowledge, a clean-testimony run in flight, or the numbers changed since the page loaded. |
| `campaign_position` | `ApproveCampaignPositionService` | Missing summary, invalid stance, a draft identity naming no draft, a run in flight, or coverage not acknowledged. |
| `campaign_organization` | `LinkCampaignOrganizationService` | A campaign belonging to another bill, an unrecognised decision value, a link with no organization chosen, an organization that no longer exists, or one from a different locale than the bill. |
| `sending_service` | `SetSendingServiceDomainLabelService` | An unknown label value. The row keeps its previous label — there is no optimistic update to roll back. |

## Why a fixed union instead of `string`

`TRefusalKey` is a fixed set of allowed strings rather than plain `string`
so that a mistyped key fails at compile time instead of compiling fine and
quietly reading `undefined` — the exact silent failure
`notifyServerRefusal` exists to end. It also means adding a new caller for
a new key is a change the compiler checks, rather than a copy-paste that
can silently miss a spot.
