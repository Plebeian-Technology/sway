---
lat:
  mode: reference
---
# Domain entities

The record types Sway's domain is built from, grouped by the question each group answers. Canonical names follow `docs/terminology.md`; the vocabulary's reasoning is in [[naming-decisions#Two vocabularies, one per actor]].

## Jurisdiction and geography

A `SwayLocale` is a jurisdiction and the top-level scope for almost everything else. Three are supported: Baltimore City (MD), State of Maryland, and US Congress.

- `SwayLocale` — `has_many :bills`, `:districts`, `:organizations`, `:legislative_sessions`; `has_one :current_legislative_session`; `nominatim_viewbox`, `nominatim_country_codes`, `nominatim_bounded` supply geographic bounds for address autocomplete. Unique on `(city, state, country)`; name is `city-state-country`; `state` is a pending rename to `region_name`
- `LegislativeSession` — `belongs_to :sway_locale`, `has_many :bills`, `has_many :legislator_terms`. Unique on `(sway_locale_id, name)`; attributes `name`, `start_date`, `end_date`, `active`; scopes `active`, `containing_date`
- `District` — `belongs_to :sway_locale`, `has_many :legislator_terms`. Carries GeoJSON boundaries; `number` and `region_code` derive from the name
- `Legislator` — `belongs_to :sway_locale`, `has_many :legislator_terms`, `:legislator_votes`, and `:bills` as sponsor with `restrict_with_exception`. `legislator_identifiers` hold upstream ids
- `LegislatorTerm` — `belongs_to :legislator`, `:district`. Unique on `(legislator_id, term_start_year)`; `began_on` and `ended_on` each record a `*_source`

## Bills

A `Bill` is a piece of proposed law within one locale. It is also the anchor for pipeline artifacts, the generated summary, and the Bill of the Month slot.

- `external_id` — upstream identifier, unique per `sway_locale_id`
- `archived_at` — explicit archive timestamp; eligibility, preserved history and visibility are defined in [[bill-session-archiving]]
- `legislator_id` — the sponsoring legislator; the wire name is `sponsor`
- `legislative_session_id` — `belongs_to :legislative_session, optional: true`; links bill to governing temporal session; `active` delegates to `legislative_session.active?` when present; `Bill.current_legislative_session` scopes to active session via the association or falls back to checking `introduced_date_time_utc` against session dates when nil
- `scheduled_release_date_utc` — Bill of the Month slot, unique per locale, so one bill per locale per day
- `introduced_date_time_utc`, `house_vote_date_time_utc`, `senate_vote_date_time_utc` — date-times carrying their zone in the name
- `has_one :bill_score` — the locale-wide user tally
- `has_many :votes` — `RollCall` records ordered by `created_at`; the association name still carries the old word
- `has_many :legislator_votes` — one per legislator who voted
- `has_many :active_organization_bill_positions` — a filtered association, so `.includes` preloading still works
- `has_many :campaigns` — testimony campaigns, destroyed with the bill
- `has_many :user_bill_shares` — per-user share links with redemption tracking, destroyed with the bill
- `has_many :bill_views` — per-user view records, destroyed with the bill

## Votes and positions

Three tables store `FOR` / `AGAINST` / `ABSTAIN`, and one of them refuses the third value. `LegislatorVote::Support` is the single definition of the constants.

- `UserVote` — cast by a user; `FOR` or `AGAINST` only; one row per `(user_id, bill_id)`
- `LegislatorVote` — cast by a legislator; all three values; carries a `source` recording where it came from
- `OrganizationBillPosition` — held by an organization; stored as vote words, displayed as Support / Oppose / Neutral; one per `(bill_id, organization_id)`; `active` gates visibility (`activated_at` is set when `active` becomes true)
- `RollCall` — the roll-call record rather than a cast vote; one row per bill; holds upstream roll-call numbers; unused by Baltimore

## Scores

Five aggregates, each answering a different question, all rebuilt by `ScoreRecomputeService`. Why they are not derived from one another: [[scores-and-agreement#The five score families]].

- `BillScore` — one per bill: how did the whole locale vote on this bill?
- `BillScoreDistrict` — bill × district: how did this district vote on this bill?
- `LegislatorDistrictScore` — per legislator term: how often did this legislator match their own constituents?
- `LegislatorLocaleScore` — per legislator term: how often did they match the whole jurisdiction?
- `UserLegislatorTermScore` — user-legislator pair × term: how often did this user and this legislator agree?

## People and identity

A `User` is a verified phone number with passkeys, an address, and per-locale legislator assignments. The model is covered by [[identity-and-access#The phone number is the account]].

- `Passkey` — a WebAuthn credential; label unique per user, `external_id` globally unique
- `RefreshToken` — one per user; the encrypted cookie backing web sessions
- `ApiKey` — bearer token for mobile, scoped to a `UserDevice`, 90-day expiry
- `UserDevice` — one mobile install; carries platform, app version and push token
- `UserLegislator` and `UserDistrict` — the two links written at registration for each matched legislator
- `Address` and `UserAddress` — the geocoded address registration resolves districts from
- `Invite` and `UserInviteLink` — referral records feeding the sway count
- [[app/models/user_bill_share.rb#UserBillShare]] — tracks per-user per-bill share link generation and redemption; unique on (user_id, bill_id) and share_uuid; feeds sway influence on redemption
- [[app/models/bill_view.rb#BillView]] — one row per `(user_id, bill_id)` recording distinct signed-in bill views, destroyed with the user
- `NotificationPreference`, `PushNotificationSubscription`, `UserBillReminder` — notification opt-ins, web push endpoints, per-bill reminders

## Organizations and campaigns

Organizations are advocacy groups scoped to a locale. They hold positions on bills and run testimony campaigns.

- `Organization` — `belongs_to :sway_locale`; name unique per locale; followers via `organization_follows`
- The `Sway` organization is seeded in every locale by `SeedSwayOrganization` during `db:seed`, before any other organization exists there
- `OrganizationBillPosition` — `active`, `support`, `summary`, `origin` (provenance label), `origin_url` (source link); (a change to any of the three notifies followers); `activated_at` is set when `active` becomes true. Positions are either "affiliated" (managed by the organization via active membership) or "compiled" (managed by Sway, and labeled accordingly).
- `OrganizationBillPositionChange` — the audit trail of edits awaiting approval
- `Campaign` — `belongs_to :bill`, optional `:organization`; name unique per bill; `organization_link_decision` records a four-state match outcome
- `UserOrganizationMembership` — membership, with a separate invite record for pending ones
- [[app/models/organization_notification_delivery.rb#OrganizationNotificationDelivery]] — immediate-delivery marker that prevents duplicate sends for the same position, user, change type, and event token
- [[app/models/pending_organization_digest_entry.rb#PendingOrganizationDigestEntry]] — durable queue entry for a user's daily or weekly organization digest

## Pipeline and admin records

Rows produced by the legislation pipeline and by admin tooling. The run lifecycle is covered by [[legislation-pipeline#Runs, resume and restart]].

- `LegislationPipelineRun` — one operator-initiated run: requested stages, status, `download_missing_assets`
- `PipelineRunStage` — per-stage outcome within a run
- `PipelineRunBill` — per-bill outcome within an all-bills run
- `PipelineActivityLogEntry` — the operator-visible activity stream, pruned by a cleanup job
- `BillLlmProvisioning` — summary-generation state for one bill
- `AdminSetting` — database-stored tunables, including every LLM knob
- `AdminBillView` — the admin's last-viewed bill state
- `Category` and `BillCategory` — subject tags; the legacy `bills.category` column is scheduled for removal
