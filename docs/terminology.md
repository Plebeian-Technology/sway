# Sway Terminology

Canonical vocabulary for code, schema, user copy, and docs. Decided
from the terminology audit. When you
name a new thing, use the terms on this page.

Some decided renames are not executed yet. The "Pending renames" table tracks
them. Until a rename lands, the old name stays in code. Do not half-migrate a
name inside an unrelated change.

**No going-forward-only rules.** A rule that binds only new code creates a
third state — old name, new name, and the confusion between them. Every
decided change migrates the entire codebase, tracked in the pending table.
A name is in exactly one of three states: canonical, pending migration, or
exempt for a stated reason (third-party contract, upstream API vocabulary,
frozen migration history, platform convention). Comments migrate in the same
commit that renames their file's code.

## Naming principles

1. **Consistency beats brevity, and context beats short.** A verbose name that
   says why the thing exists is preferred. Example ruling:
   `legislation_pipeline_run` is preferable to `pipeline_run` — the long form
   says why Sway has a pipeline at all. Use the full contextual form for new
   names. When two classes expose the same concept, they must use the same
   name for it.
2. **A name that carries an amount must name the units.** This applies to
   methods, variables, columns, and constants. Examples:
   `time_since_introduction_ms` (milliseconds), `weight_in_lbs` (pounds),
   `byte_size` (bytes). Date-times that carry a timezone name it
   (`vote_date_time_utc`).
3. **Third-party contract names are untouchable.** A keyword another library
   or integration reads keeps its name, whatever our conventions say:
   `timeout:` in `config/database.yml` (SQLite), Faraday option keys, Rails
   `expires_in:`, GCS `max_age:`, React Native props. Our conventions apply
   one layer up — the Sway-owned wrapper that feeds the value carries the
   unit and context (a `timeout_seconds:` parameter on our HTTP factories
   assigns into Faraday's own `timeout` option, which keeps its name).

## Votes and positions: two vocabularies, one per actor

Users and legislators **cast votes**. A vote is **For**, **Against**, or
**Abstain**. Organizations **hold positions**. A position is **Support**,
**Oppose**, or **Neutral**. Do not mix the two sets. An organization never
"votes For". A user never "Supports" a bill.

- Stored values stay `FOR` / `AGAINST` / `ABSTAIN` on all three tables
  (`user_votes`, `legislator_votes`, `organization_bill_positions`). Org
  surfaces translate them to Support / Oppose / Neutral at display time.
- The column name `support` stays for now. A rename costs a three-table
  migration plus the mobile wire.
- "stance" is retired as a noun in copy and comments. Write "vote" (people) or
  "position" (organizations).
- Upstream sources (Legistar, congress.gov, OpenStates) keep their own words
  at the boundary. Each scraper or client casts them to ours.
- A Neutral organization position keeps no testimony. Ingestion discards it
  (behavioral rule, implementation tracked separately).

## Canonical domain terms

| Concept                                                    | Canonical term                                                                                                 | Rejected / notes                                                                                                                                                                                                     |
| ---------------------------------------------------------- | -------------------------------------------------------------------------------------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| A piece of proposed law                                    | `bill`                                                                                                         | "legislation" is acceptable as user-facing prose, never as an identifier for the domain object                                                                                                                       |
| The fetch/processing machinery                             | `legislation pipeline`, `LegislationPipelineRun`                                                               | Kept whole after review. The shorter `pipeline_run_*` children rename to the full prefix (pending table); new names in this family use the full `legislation_pipeline` context (naming principle 1)                  |
| A geographic jurisdiction                                  | `sway_locale` in ALL code                                                                                      | Bare `locale` in code is reserved for Rails I18n. User copy can say "locale" (deliberate split, below)                                                                                                               |
| An elected official                                        | `legislator`                                                                                                   | "member" and "representative" are boundary vocabulary, never class names. `sponsor` = the bill's sponsoring legislator (wire name for `bills.legislator_id`)                                                         |
| An advocacy group                                          | `organization`                                                                                                 | Never abbreviate to "org" in new names. Existing `org_*` tables/columns migrate later (see pending renames)                                                                                                          |
| The roll-call record on a bill                             | `RollCall`                                                                                                     | One row per bill. Holds the decisive vote's upstream roll-call numbers. Congress and OpenStates use it. Baltimore does not                                                                                           |
| A user's cast vote                                         | `UserVote`                                                                                                     |                                                                                                                                                                                                                      |
| A legislator's cast vote                                   | `LegislatorVote`                                                                                               |                                                                                                                                                                                                                      |
| Subject tags on bills                                      | `category` / `categories`                                                                                      | Not "topical categories", "topic", or "issues". The dead `bills.category` column is scheduled for removal                                                                                                            |
| The gamification currency                                  | `sway` ("Your Sway")                                                                                           | A user's influence/clout. Never use "sway" for the agreement metric                                                                                                                                                  |
| The user-legislator agreement metric                       | `voter agreement`                                                                                              | "Sway score" is retired for this metric                                                                                                                                                                              |
| State/province of an address or locale                     | `region_name` (full name), `region_code` (two-letter code)                                                     | "state" is rejected: it does not fit non-US locales. `sway_locales.state` → `region_name` is pending                                                                                                                 |
| Application-level admin                                    | `sway_admin` (`is_sway_admin?`, `verify_is_sway_admin`)                                                        | Unqualified "admin" is reserved for organization-scoped admins. The wire prop `is_admin` → `is_sway_admin` is pending (mobile compat)                                                                                |
| The featured monthly bill                                  | "Bill of the Month" in copy, `bill_of_the_month` in code. No abbreviation is sanctioned                        | `botw_announcement` is retired (migrated to `botm_announcement`, the only key the server accepts). The other wire keys are frozen                                                                                    |
| The admin tool that builds bills                           | "Bill Creator", `BillCreatorPage`                                                                              |                                                                                                                                                                                                                      |
| A shareable referral code                                  | `user_invite_links`                                                                                            | "invite" in identifiers, "invitation" in user copy                                                                                                                                                                   |
| The passwordless credential                                | `passkey` for everything Sway-owned                                                                            | "WebAuthn" and "credential" only at the protocol boundary. `users.webauthn_id` stays (accepted)                                                                                                                      |
| A legislative session                                      | `legislative_session` wording in new code                                                                      | Bare `session` means the browser session. `Bill.current_session` → `current_legislative_session` pending                                                                                                             |
| A message a user sent to a legislator                      | `UserLegislatorEmail` is a message with delivery state                                                         | Not an address. `users.email` and `legislators.email` are addresses                                                                                                                                                  |
| The compute host executing weights behind a routing broker | `upstream company` (policy/admin), `upstream endpoint` (routing/network), `pinned upstreams` (code collection) | Never use `provider` (which means the adapter class, stored draft provenance `llm_provider`, or adapter label `provider_label`). Do not use `vendor`, `host`, `backend`, or `server` for the upstream inference host |

## Stored-file terms

Each word names one storage mechanism. Do not swap them.

| Term         | Means                                                 |
| ------------ | ----------------------------------------------------- |
| `attachment` | An Active Storage object                              |
| `artifact`   | The pipeline's on-disk cache under `LEGISLATION_ROOT` |
| `asset`      | Admin-uploaded media in the GCS bucket                |
| `mirror`     | The copy-an-external-asset mechanism                  |
| `upload`     | The act of sending a file                             |

## Fetch machinery layers

These are layers and stages, not synonyms.

| Term                 | Means                                             |
| -------------------- | ------------------------------------------------- |
| `Scraper::`          | The raw upstream HTTP/parse layer (`app/scraper`) |
| `*VoteUpdateService` | Orchestration that wraps scrapers                 |
| `Fetch*Service`      | Pipeline stage fetchers                           |
| ingestion            | The post-fetch database write phase               |
| seed                 | Boot-time invocation of the pipeline              |

## Eval harness vocabulary

Six terms for the "is the model's answer any good" harness under `eval/` and
`app/services/eval/`. Use these, not ad hoc synonyms, in the rake tasks, the
promptfoo config and the report.

| Term               | Means                                                                                                                           |
| ------------------ | ------------------------------------------------------------------------------------------------------------------------------- |
| `candidate`        | A model whose answer is being measured, identified by its provider AND its pinned model id together, never by a bare model name |
| `reference answer` | The anchor an answer is compared against — written outside the harness (a Claude Code session), arriving as committed data      |
| `verdict`          | One judge record per bill, answer type and candidate                                                                            |
| `dimension`        | One named quality being scored, on the 0–4 scale                                                                                |
| `answer type`      | `summary` or `positions` — the two kinds of model answer this phase measures                                                    |
| `judge`            | The model that scores. Never also a candidate — no answer is graded by the model that wrote it                                  |

A candidate's identity key is the pair `(provider, model id)`, not the model
name alone. The phase moves Sway from one provider to several, and the same
weights can be served by two companies at two configurations under one name —
a bare model name cannot distinguish them, and the roster this phase measures
already carries a model reached three different ways. Every answer fixture
records both fields, and the scoring pass refuses to aggregate two different
observed model ids under one candidate label.

The local llama.cpp server's loaded model is read from its models endpoint at
answer time, not copied from config: the shared server answers as a different
model than the roster names as of this writing, and it can change again
mid-run.

## LLM inference and routing terms

These terms distinguish the routing broker and client adapter from the physical compute host executing model weights.

| Term                | Means                                                                                                                                                                                                                                                                                                                      | Rejected / prohibited                                                                         |
| ------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | --------------------------------------------------------------------------------------------- |
| `provider`          | The client adapter interface, billing account, or stored draft provenance (`claude`, `llamacpp`, `openrouter`, or `operator_paste`). Carries three code meanings: `Sway::Settings.llm.llm_provider` (adapter factory), `bill_llm_provisionings.llm_provider` (stored provenance), and `provider_label` (telemetry string). | Never use `provider` for the company operating the inference infrastructure behind a gateway. |
| `upstream company`  | The organization operating the infrastructure that executes model weights behind a gateway (e.g. `DeepSeek`, `Fireworks`, `Together`). Used in policy, admin copy, and data governance.                                                                                                                                    | `provider`, `vendor`, `backend`                                                               |
| `upstream endpoint` | The specific network host or routing target evaluated by the gateway for a given model. Used in routing contracts, telemetry logs, and error types.                                                                                                                                                                        | `host`, `server`, `provider`                                                                  |
| `pinned upstreams`  | The ordered list of authorized upstream companies declared in request payloads (`provider.order`) or configuration collections.                                                                                                                                                                                            | `allowed providers`, `vendor list`                                                            |

## Notification kinds

`notification` is the umbrella term. `reminder` (`user_bill_reminders`) and

`digest` (batched org deliveries) are real sub-kinds and stay. Do not invent
new kind words ("alert", "announcement"). `botm_announcement` is a frozen wire
key, not a pattern. Its retired predecessor `botw_announcement` was migrated to
it and the server no longer accepts it.

## Deliberate code-vs-copy splits

These look inconsistent. They are decisions, not drift.

| Code says            | User copy says           | Why                                                           |
| -------------------- | ------------------------ | ------------------------------------------------------------- |
| `sway_locale`        | "Locale" / "your locale" | "Sway locale" is harder for non-admin users                   |
| `legislator`         | "Representatives"        | Friendlier, and documented here as the deliberate translation |
| invite (identifiers) | "invitation"             | Natural English in copy                                       |

## Frozen wire keys

Never rename these without a mobile compatibility plan: `is_admin` (until the
pending `is_sway_admin` migration), `botm_announcement`, `org_position_taken`,
the `legislation_pipeline_run` Inertia/ActionCable prop, and every serializer
key pinned by `spec/requests/serializer_whitelists_spec.rb`.

## Pending renames (decided, not yet executed)

| From                                                                                                                                                         | To                                                                                         | Size                                                                                                                                                               |
| ------------------------------------------------------------------------------------------------------------------------------------------------------------ | ------------------------------------------------------------------------------------------ | ------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| `useLocale`, `LocalePicker`, `by_locale`, other bare-locale identifiers                                                                                      | `useSwayLocale`, `SwayLocalePicker`, `by_sway_locale`, same rule throughout                | mechanical, wide. The backend locals and the spec lets, locals and helper parameters are already migrated; the frontend, mobile and the `by_locale` scopes are not |
| `ApproveOrgPositionService` and other org-named classes/screens                                                                                              | spelled-out Organization names                                                             | mechanical                                                                                                                                                         |
| `users.org_position_cadence_default`                                                                                                                         | `users.organization_position_notification_cadence_default`                                 | column migration                                                                                                                                                   |
| `bills.category` column                                                                                                                                      | (removed)                                                                                  | migration + serializer whitelist + seeds                                                                                                                           |
| `sway_locales.state`                                                                                                                                         | `region_name`                                                                              | migration + SwayLocale name parsing + seeds                                                                                                                        |
| `is_admin?` alias + `is_admin` wire prop                                                                                                                     | `is_sway_admin?` / `is_sway_admin`                                                         | Ruby alias trivial. Wire needs mobile compat                                                                                                                       |
| `Bill.current_session`                                                                                                                                       | `current_legislative_session`                                                              | rename                                                                                                                                                             |
| `PipelineRunBill` / `PipelineRunStage` models, `pipeline_run_bills` / `pipeline_run_stages` tables, `pipeline_runs_controller`, `usePipelineRunSubscription` | `LegislationPipelineRunBill` / `LegislationPipelineRunStage` etc. — the full family prefix | migrations + controller + frontend hook + RBS                                                                                                                      |
| The AI draft-position "stance" vocabulary (schema files, stored `BillLlmProvisioning` JSON, draft controllers/services, TS `TStance`)                        | `support`/position vocabulary                                                              | stored rows + LLM contract + admin forms — one planned project                                                                                                     |
