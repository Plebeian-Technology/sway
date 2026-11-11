---
mode: explanation
summary: "Explains how OpenLegislator::Client resolves native legislation records, consumes composite payloads, and preserves Legistar fallback in vote updates."
status: agent-extracted
related: []
---
<!-- vale Vale.Spelling = NO -->

# Open Legislator native client architecture and fallback design

The native Open Legislator integration enables Sway to query municipal legislation directly through Open Legislator's public read API rather than relying on legacy Granicus Legistar Web API endpoints.

## Why a native Open Legislator client exists

Granicus Legistar Web API endpoints often exhibit unreliability, lack consistent versioning, and require multiple waterfall queries to reconstruct a matter's history and vote outcomes.

Open Legislator exposes clean REST endpoints under `/api/v1` with bounded pagination, canonical slug identifiers, and composite matter payloads that provide full legislative context in a single request.

## Legislative file number resolution and composite payload consumption

`OpenLegislator::Client` resolves natural legislative file numbers through a two-step retrieval pattern that mirrors standard civic search workflows.

The client first issues a filtered collection lookup to `/api/v1/matters?file_number=:file_number` to obtain the canonical matter slug from the `data` array. It then queries the composite detail endpoint at `/api/v1/matters/:slug`, which delivers sponsorships, topic tags, attachments, and published action histories with roll-call vote tallies without issuing secondary N+1 requests.

## Pagy pagination envelope alignment

Collection endpoints in Open Legislator emit pagination metadata inside a dedicated `page` envelope.

The Pagy envelope standardizes four numeric fields: `page` (current page number), `last` (final page number), `count` (total records in the filtered scope), and `limit` (page size). The multi-page traversal method `#all_matters` terminates cleanly when the current page index reaches `last`, avoiding arbitrary page offsets or missing collection boundaries.

## Wire contract truthfulness and action outcome enums

Action records in Open Legislator enforce civic truthfulness by restricting published results to canonical vocabulary values.

Under `MatterAction::RESULTS`, valid action result enums are strictly `"pass"`, `"fail"`, or `null` when no outcome was published. Similarly, `MatterStatus::OUTCOMES` restricts status outcomes to `%w[pending enacted failed withdrawn unknown]`. When a matter record lacks a passing action or enacted outcome, the service logs an honest non-event rather than manufacturing synthetic votes or guessing passage dates.

## Resilient dual-source architecture and Legistar fallback

`GenericLegislatorVoteUpdateService` supports an explicit `source: :open_legislator` option while safeguarding continuous operational data synchronization.

If Open Legislator returns an HTTP error, encounters a network timeout, or returns a missing record (`nil`), the service logs an explanatory warning and delegates the lookup to the legacy `Legistar::Client`. This dual-source design ensures that migrations to the native API remain non-blocking for existing vote-tracking and constituent-facing score pipelines.
