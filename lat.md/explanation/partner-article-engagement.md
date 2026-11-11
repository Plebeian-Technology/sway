---
lat:
  mode: explanation
---
# Partner article engagement

Partner article engagement measures civic actions driven by newsroom coverage while mathematically preserving secret ballot integrity.

Related concepts include [[embeddable-bill-widget]], [[registration-funnel-telemetry]], and [[identity-and-access]].

## Data model and join relationship

The ArticleBill join table connects partner newsroom organizations to specific legislative bills covered in their reporting.

Each `ArticleBill` record belongs to both an `Organization` and a `Bill`. The model requires the presence of `bill_id`, `organization_id`, `partner_slug`, `article_url`, and `article_title`. A compound unique database index on `[:bill_id, :article_url]` prevents duplicate pairings while permitting an article covering multiple bills to link cleanly to each bill.

## Counter cache architecture

Atomic integer counter caches on the join record track engagement without recording individual voter identities or ballots.

The schema establishes `clicks_count`, `registrations_count`, `votes_count`, `pro_votes_count`, and `con_votes_count` directly on `article_bills`. When readers interact with covered bills, `ArticleEngagementTrackerService` increments these counters using database-level atomic operations (`increment_counter`). This architecture prevents concurrent update collisions while avoiding any persistent link between voter identity and article records.

## End-to-end attribution lifecycle

Attribution parameters travel from embedded widgets through top-level navigation to registration and ballot submissions.

When a reader clicks the call-to-action link in an embedded widget, `ApplicationController#capture_attribution_param` records the partner identity and optional article reference into `cookies.permanent[:sway_attribution_key]` as `partner:<partner_slug>:<ref>`, resolves the `ArticleBill` (scoped to the active bill when visiting bill routes), and invokes `ArticleEngagementTrackerService.track_click` once per session. Session fixation protection in `sign_in` preserves this cookie across authentication boundaries. When a new user completes registration, `ArticleEngagementTrackerService.track_registration` increments the associated counter, and subsequent ballot submissions invoke `ArticleEngagementTrackerService.track_vote`.

## Privacy guarantees and k-anonymity

Strict privacy invariants protect ballot secrecy and prevent reader profiling through structural separation and k-anonymity.

Neither `users` nor `user_votes` contains any foreign key or relationship to `article_bills`. Because counts are incremented atomically at transaction time without storing relational ties, ballot secrecy remains absolute. Furthermore, to defend against reader de-anonymization in small sample sizes, `PartnerEngagementReportService` enforces k-anonymity suppression: when `total_votes < 5`, directional percentages (`pro_percentage` and `con_percentage`) are suppressed and return `nil`.

## Newsroom reporting and Alba serialization

Partner engagement metrics aggregate article coverage and civic actions for newsroom grant reporting and reader retention analysis.

Nonprofit newsrooms report verified civic impact metrics to philanthropic funders such as Press Forward and the Knight Foundation. `PartnerEngagementReportService` aggregates total articles published, distinct bills covered, referral clicks, verified constituent registrations, total votes cast, and sentiment distributions. `PartnerEngagementReportResource` serializes this data through a strict Alba whitelist without personal identifiable information.

## Administrative interface

Administrative controllers provide Sway staff with visibility into newsroom partner engagement metrics and article performance.

`Admin::PartnerReportsController` provides `index` and `show` actions protected by `before_action :verify_is_sway_admin`. The index action lists all partner organizations with coverage metrics, while the show action details performance metrics and covered articles for a selected newsroom partner.
