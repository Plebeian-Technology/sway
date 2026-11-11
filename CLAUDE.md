# CLAUDE.md

<!-- vale Vale.Spelling = NO -->

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What is Sway

Sway is a civic engagement platform where users vote on the same legislation as their elected representatives, enabling accountability tracking. Built as a Rails + React monolith using Inertia.js for server-driven rendering.

Supported locales: Baltimore City (MD), State of Maryland, US Congress.

## Tech Stack

- **Backend:** Rails 8.1 / Ruby 4.0.7 / SQLite (WAL mode)
- **Frontend:** React 19 / TypeScript 6.0 / Vite 8 / Radix UI + Tailwind CSS 4
- **Bridge:** Inertia Rails (server-driven React props, no client-side routing)
- **Jobs:** Solid Queue with separate SQLite database
- **Auth:** WebAuthn (passkeys) + Twilio SMS verification
- **Real-time:** ActionCable WebSockets for score sync
- **Deployment:** Kamal, Docker (Alpine), Caddy reverse proxy, Cloudflare tunnel

## Development Commands

The dev environment runs entirely under Docker via `dip`. SQLite databases
live in the `sway_storage` Docker named volume — running Rails directly on
the host hits a different (empty) `storage/` dir and is blocked at boot
(see `config/boot.rb`). Set `SWAY_ALLOW_HOST_RAILS=1` only for true edge
cases.

```bash
# First-time provision: build images, mkcert certs, drop and recreate the dev/test/preview databases
dip provision

# Start the full dev stack (rails, vite, caddy, jobs, cloudflared)
dip run dev          # browse at https://localhost:3333 (Caddy → web:3000 / vite:3036)

# One-off rails commands (all hit the same named-volume DB)
dip run rails c                        # console
dip run rails seed                     # db:seed + db:seed:bills + score recompute
dip run rails db:migrate
dip run bundle exec rake <task>        # focused rake tasks go through `bundle exec`
```

Bill seeding (`db:seed:bills` / `dip run rails seed`) calls llama.cpp on
`host.docker.internal:8888` for summaries — start `llama-server` on the host
first or that step fails with connection-refused. Plain `db:seed`/`db:reset`
don't need it.

### Testing & Linting

```bash
dip run verify                         # Parallel gate — see the caveat below; takes NO arguments and refuses them. Exit 0 all lanes green, 1 a lane failed, 2 a lane did not complete

dip run rspec                          # Full backend suite (vite test build first; takes NO arguments and refuses them). Application errors go to the local collector — see docs/operations.md
dip run bundle exec rspec spec/models/           # Focused runs go through `bundle exec`
dip run bundle exec rspec spec/path_spec.rb      # Run a single test file
dip run bundle exec rspec spec/path_spec.rb:42   # Run a single example by line

dip run vitest                         # Frontend unit/component tests — runs on the HOST (the image's Node is not the pinned one); takes file paths
# Live Claude API verification (costs ~$0.02 per run; explicit opt-in to avoid
# accidental billing). Requires ANTHROPIC_API_KEY in your env AND
# explicit RUN_LIVE_LLM_TESTS=1.
dip run bash -c "RUN_LIVE_LLM_TESTS=1 bundle exec rspec spec/integration/llm/claude_adapter_integration_spec.rb"

# Lint/format (no DB, can run on host)
pnpm lint                              # oxlint — TypeScript/React linting (config: .oxlintrc.json)
pnpm lint:fix                          # oxlint --fix
npx tsc                                # TypeScript type checking
pnpm fmt                               # oxfmt — format JS/TS (4-space)
pnpm fmt:check                         # oxfmt --check

# Ruby lint & types
bin/rubocop                            # Standard Ruby (host-runnable, no DB)
dip run steep                          # RBS type check via steep on the host, information severity, about five seconds
bin/steep check --severity-level=information      # the same check for a container or CI where dip is absent
```

`dip run verify` (`scripts/dip/verify.sh`) runs fifteen lanes at the same time
and writes each one's result to `tmp/verify/summary.json`. Eleven on the host —
`rubocop`, `vitest`, `tsc`, `oxlint`, `oxfmt`, mobile Jest, mobile typecheck,
mobile `oxlint`, `brakeman`, `rbs validate` and `steep` — and four
in Docker: the `sway:lint:*` rake gates, a sharded browser rspec lane, a
sharded non-browser rspec lane and tesseract parity. Each rspec worker gets its
own SQLite file on a RAM filesystem, and the frontend is built once per run into
its own directory, so two runs at once cannot corrupt each other. A green
`dip run verify` is a green suite; the commands above stay useful for focused
work.

System specs (`spec/system/`, Capybara + Selenium) run inside the dip rspec
image (ships chromedriver) or on the macOS host via Selenium Manager; they
self-skip with a logged message when no Chrome/Chromium binary is found.

## Architecture

### Inertia.js Pattern (Critical)

Sway uses Inertia.js - Rails controllers render React pages by passing props, not JSON APIs. No client-side router exists.

- Controllers call `render inertia: "PageName", props: { ... }` instead of returning JSON
- React pages receive data as props, not via fetch/axios
- Form submissions use `useForm` from `@inertiajs/react`, not direct API calls
- Admin bill creator forms use `useForm` (from `@inertiajs/react`) shared via `SwayFormContext` (`app/frontend/components/admin/creator/context/`), with submission through `useBillFormSubmit`'s `transform()` at request-build time — not the `<Form>`/`useFormContext` component API
- Score updates use a hybrid: ActionCable push triggers `router.reload({ only: [...] })` partial reloads, with `usePoll(15000)` as fallback on user-facing pages (Bill, BillOfTheMonth, Legislators, Legislator, Influence, Organizations, Organization). Admin Bill Creator surfaces (BillCreatorPipelineLlm, BillCreatorSummaryAndPositions) poll tighter at 5s for in-flight pipeline visibility.
- `router.reload` preserves scroll and component state on its own, and its `ReloadOptions` type has no `preserveScroll` key — passing one is a TypeScript error. `router.visit`/`router.get`/`form.post` callers pass `preserveScroll: true` explicitly

Use the follow skills when working with inertia and inertia-rails on the frontend or backend:
- inertia-rails-best-practices
- inertia-rails-performance
- inertia-rails-cookbook
- inertia-rails-forms
- inertia-rails-architecture
- inertia-rails-controllers
- inertia-rails-pages
- inertia-rails-setup
- inertia-rails-testing
- inertia-rails-typescript
- alba-inertia
- shadcn-inertia

### Backend Structure

- `app/controllers/` - Rails controllers (render Inertia props to React pages)
- `app/models/` - ActiveRecord models (User, Bill, Legislator, BillScore, UserVote, etc.)
- `app/services/` - Service objects (SwayRegistrationService, ScoreUpdaterService, InfluenceService)
- `app/serializers/` - alba resources (`FooResource < ApplicationResource`) for all JSON/prop serialization
- `app/jobs/` - Solid Queue background jobs (score updates, notifications, SMS delivery)
- `app/channels/` - ActionCable channels (ScoreChannel for real-time score sync)

### LLM Bill Summaries

`app/services/llm/` is an adapter layer behind `Llm::Client`: production uses
the Claude API via `ClaudeAdapter` (`anthropic` gem); dev/test use
`LlamacppAdapter` against a host llama.cpp server (`LLAMACPP_BASE_URL`,
default `host.docker.internal:8888`). Admin-tunable LLM settings live in the
DB (`admin/llm_settings`), not env/config.

### Legislation Pipeline

The legislation pipeline runs natively in Rails (it replaced a former
Python sidecar, whose archived source was deleted July 2026):
`app/services/legislation/`, `app/services/legistar/` (`Legistar::Client`),
and `LegislationPipelineRunService` fetch upstream data — Baltimore Legistar,
hearing PDFs — for bill seeding and pipeline runs. `app/services/testimony/`
(`Testimony::CleanAndGroupService` and friends) runs the clean-testimony
stage that groups and classifies hearing-testimony letters after they're
fetched. The repo-root `legislation/` dir holds only untracked runtime
artifacts (`LEGISLATION_ROOT`). Operator docs: `docs/operations.md`.

### Frontend Structure

- `app/frontend/pages/` - Inertia page components (top-level, receive server props)
- `app/frontend/components/` - Reusable React components
- `app/frontend/hooks/` - Custom hooks (useScoreSubscription, etc.)
- `app/frontend/channels/` - ActionCable consumer setup
- `app/frontend/sway_constants/` - App constants
- `app/frontend/sway_utils/` - Utility functions

### Mobile App

`mobile/` is an Expo React Native app (separate pnpm workspace) consuming the
same Rails backend via bearer-token JSON (`/api/v1`). Free-tier Expo only —
builds run locally via `eas build --local`, never paid EAS services.

```bash
pnpm --dir mobile test                 # Jest (TZ=UTC)
pnpm lint:mobile                       # oxlint (mobile has its own .oxlintrc.json)
pnpm --dir mobile run typecheck        # tsc --noEmit
```

### Key Domain Concepts

- **SwayLocale** - A geographic jurisdiction (city/state/federal) with its own bills, legislators, and districts
- **BillScore** - Aggregated voting data per bill (district-level and locale-level)
- **UserVote** - A user's vote on a bill, compared against their legislator's vote
- **District** - Geographic area with GeoJSON boundaries, links users to legislators
- **Bill of the Month** - Admin-curated featured legislation with scheduled notifications

### Registration Flow

Uses a state machine (`state_machines-activerecord`): `pending` → `processing` → `completed` / `failed`. Registration is async because it involves geocoding addresses and assigning legislators via external APIs.

## Code Style

- **Ruby:** Double quotes, 2-space indent, Standard Ruby (standardrb via RuboCop with rails/performance/custom plugins); no trailing commas in multiline Ruby literals; pre-commit runs rubocop on staged Ruby files with safe autocorrect (`--autocorrect`, never `-A`), then re-stages whole files — so re-read any committed line whose correctness depends on exact spelling
- **TypeScript/JS:** Double quotes, 4-space indent, trailing commas, semicolons; components are `const X: React.FC<IProps>` arrow-consts with `interface IProps` and a single `export default` (exception: `components/ui/` is a vendored shadcn island with its own conventions)
- **Comments:** A comment states a bare fact only — an `@lat: [[section-id]]` pointer into `lat.md/`, or a single-clause note (a unit, a bound, what nil means). The test is not length, it's whether the comment explains *why* — a reason, trade-off, rejected alternative, constraint, or an invariant's rationale. Any comment that does is documentation, not a comment: write or extend a section in the matching `lat.md/{tutorials,how-to,reference,explanation}/` file (use the `diataxis` skill to classify; extend an existing section before adding a new one), and leave a bare `@lat:` pointer behind — never a paragraph. Never narrate what the code does: if a reader could write the comment from the code alone, delete the comment. A comment (or its linked `lat.md/` section) that contradicts its code is a defect — update it in the same commit that changes the code (wrong comments mislead agent readers far more than missing ones). Plain language: describe concepts, do not name-drop them. Ruby doc mood is Rails-style present indicative ("Returns a hash that..."). Rationale and evidence: `lat.md/explanation/comments-and-docs.md`. **`DOCREF <path> <tags>` comments are retired (2026-08-28) — do not write new ones.** ~1,093 files still carry the old kind, pointing into `docs/explanation/`; they are legacy and not being swept in bulk. When touching one of those files: delete the `DOCREF` line if an `@lat:` comment already covers the same seam, otherwise convert it — port the reasoning from the `docs/` file it names into the matching `lat.md/` section, then replace `DOCREF` with `@lat:`. `docs/{reference,explanation,how-to,tutorials}/` otherwise stays as read-only legacy content; it is no longer where new extraction goes.
- **Commits:** [conventional-changelog format](https://github.com/conventional-changelog/conventional-changelog-angular/blob/master/convention.md)
- **Type checking:** RBS for Ruby (signatures in `sig/`, with `rbs_rails` for Rails-generated types); maintain `.rbs` files alongside code changes
- **Terminology:** One canonical term per domain concept. The vocabulary — the vote/position word sets, deliberate code-vs-copy splits, frozen wire keys, and pending renames — lives in `docs/terminology.md`. Check it before naming anything new
- **Serialization:** New JSON/prop serialization goes through an alba resource (`FooResource < ApplicationResource` in `app/serializers/`), serialized at prop/JSON-build time via `FooResource.new(record_or_collection).serializable_hash`; never render raw ActiveRecord (`render json: record`, `.attributes`, default `as_json`). Existing `to_sway_json`/`to_builder` sites migrate opportunistically. Pin every resource's key set with an exact key-set request spec (`spec/requests/serializer_whitelists_spec.rb`). alba-inertia's controller DSL is deliberately not wired up (it replaces `render_inertia_or_json`)

## Admin Endpoints

Admin-only routes use a single convention: `before_action :verify_is_sway_admin`
(defined in `app/controllers/application_controller.rb`).

**Admin-gated controllers (authoritative list):**

- `app/controllers/bills_controller.rb`
- `app/controllers/organizations_controller.rb`
- `app/controllers/organization_bill_positions_controller.rb`
- `app/controllers/legislator_votes_controller.rb`
- `app/controllers/pipeline_runs_controller.rb`
- `app/controllers/bill_draft_org_positions_controller.rb`
- `app/controllers/admin/llm_settings_controller.rb`
- `app/controllers/admin/index_controller.rb`
- `app/controllers/admin/categories_controller.rb`
- `app/controllers/admin/locales_controller.rb`
- `app/controllers/admin/shared_addresses_controller.rb`
- `app/controllers/admin/system_prompts_controller.rb`
- `app/controllers/bills/categories_controller.rb`
- `app/controllers/bill_of_the_month_schedule_controller.rb`
- `app/controllers/testimony_coverage_acknowledgements_controller.rb`
- `app/controllers/campaigns_controller.rb`
- `app/controllers/sending_service_domains_controller.rb`
- `app/controllers/admin/bill_summary_reports_controller.rb`
- `app/controllers/admin/registration_funnel_controller.rb`
- `app/controllers/admin/partner_reports_controller.rb`
- `app/controllers/admin/bill_news_articles_controller.rb`
- `app/controllers/admin/user_address_changes_controller.rb`

**Enforcement:**

- **Positive test coverage:** every admin controller spec must
  `include_examples "requires sway admin", verb:, path:, params:`
  (defined in `spec/support/shared_examples/requires_sway_admin.rb`).
- **Lint:** `bundle exec rake sway:lint:admin_guards` fails CI if any of the
  admin-gated controllers above drops the before_action. Run it locally before
  pushing admin-controller changes.

One admin endpoint is gated by a different mechanism and is deliberately absent
from the list above: Active Storage's upload endpoint
(`POST /rails/active_storage/direct_uploads`). Its controller belongs to Rails
and never reaches `ApplicationController`, so it is guarded by
`AdminOnlyDirectUploads`, attached in `config/initializers/active_storage_admin_uploads.rb`
and covered by `spec/requests/active_storage_direct_uploads_spec.rb`.

**Adding a new admin-gated controller:**

1. Add `before_action :verify_is_sway_admin` (usually near the top of the class).
2. Append the file path to the allowlist in `lib/tasks/sway_lint.rake`.
3. Add `include_examples "requires sway admin", ...` to the controller's spec.

## Environment Variables

No file under `app/` reads `ENV` directly. Every setting is declared once in
`lib/sway/settings/<group>.rb` and read through `Sway::Settings.<group>.<name>`;
every credential goes through `app/lib/env_secret.rb`, the one path allowed to
read `ENV` at all. `bundle exec rake sway:lint:env_reads` parses (not greps)
every tracked file under `app/` and fails the build on a second one.

**Adding a setting:** declare it in the group it belongs to (or a new group)
under `lib/sway/settings/`, with a type and, unless it is genuinely required,
a default — never reach for `ENV` at the call site.

## CI/CD

GitHub Actions runs on every push: RSpec, oxlint, TypeScript type checking, Vitest, mobile Jest, Brakeman, CodeQL security analysis. All checks must pass before merge. No workflow names the machine it runs on: each reads a `CI_RUNNER` variable and falls back to `ubuntu-latest` when it is unset, which is what a fresh clone and any fork see. Set that variable where a particular runner is wanted. CodeQL runs on GitHub-hosted runners — prefer local gates (`dip run ...`, `bundle exec brakeman`, `bin/codeql-local`) before pushing. Deploys (`deploy.sh` via Kamal) are not CI-gated.

%% lat:begin %%
# Before starting work

Use Lat's knowledge graph to ground each task before changing code.

- Run `lat search` to find sections relevant to your task. Read them to understand the design intent before writing code.
- Run `lat expand` on user prompts to expand any `[[refs]]` — this resolves section names to file locations and provides context.

# Post-task checklist (REQUIRED — do not skip)

After EVERY task, before responding to the user:

- [ ] Update `lat.md/` if you added or changed meaningful functionality, architecture, tests, behavior, or planned work. Keep it a focused snapshot of current/planned state, not a journal/changelog.
- [ ] Run `lat check` — all validations must pass
- [ ] Do not skip these steps. Do not consider your task done until both are complete.

---

# What is lat.md?

Lat.md is the project's structured knowledge graph for architecture, design decisions, behavior, and tests.

The graph lives in `lat.md/` as cross-linked Markdown describing **what** the project does and **why**. Use it to ground work in actual architecture, and keep it a focused current/planned snapshot rather than a journal or changelog.

Project-specific lat documentation belongs in `lat.md/`. Do not modify this generated instruction file or a generated `lat-md` `SKILL.md` to record project guidance: both are owned by lat tooling and may be replaced by a later `lat init`.

# Commands

Use these commands to navigate, expand, and validate the project knowledge graph.

```bash
lat locate "Section Name"      # find a section by name (exact, fuzzy)
lat refs "file#Section"        # find what references a section
lat search "natural language"  # semantic search across all sections
lat expand "user prompt text"  # expand [[refs]] to resolved locations
lat external show <handle>      # inspect a pinned external source before cloning it
lat check                      # run full graph and documentation validation
```

Run `lat --help` when in doubt about available commands or options.

If `lat search` fails because no API key is configured, explain to the user that semantic search requires a key provided via `LAT_LLM_KEY` (direct value), `LAT_LLM_KEY_FILE` (path to key file), or `LAT_LLM_KEY_HELPER` (command that prints the key). Supported key prefixes: `sk-...` (OpenAI) or `vck_...` (Vercel). If the user doesn't want to set it up, use `lat locate` for direct lookups instead.

# Syntax primer

Lat uses stable section ids, wiki links, source links, and code references to connect documentation with implementation.

- **Section ids**: `lat.md/path/to/file#Heading#SubHeading` — full form uses project-root-relative path (e.g. `lat.md/tests/search#RAG Replay Tests`). Short form uses bare file name when unique (e.g. `search#RAG Replay Tests`, `cli#search#Indexing`).
- **Wiki links**: `[[target]]` or `[[target|alias]]` — cross-references between sections. Can also reference repository paths or source code: `[[schema.sql]]`, `[[src/components]]`, `[[src/foo.ts#myFunction]]`.
- **Repository path links**: Wiki links without a `#` fragment may target any existing file or directory inside the project. Unsupported formats validate but cannot be opened by Lat; fragments require a `lat.md/` section or supported source file.
- **Source code links**: Wiki links in `lat.md/` files can reference functions, classes, constants, and methods in supported source files. Use the full path: `[[src/config.ts#getConfigDir]]`, `[[src/server.ts#App#listen]]` (class method), `[[lib/utils.py#parse_args]]`, `[[src/lib.rs#Greeter#greet]]` (Rust impl method), `[[src/app.go#Greeter#Greet]]` (Go method), `[[src/app.h#Greeter]]` (C struct). When prose names an implementation symbol or a behavior governed by one, link the symbol instead of using a bare code span or copying its literal value. Prefer `[[src/config.ts#DEFAULT_TIMEOUT]]` (or an aliased form) over a bare identifier or copied value. `lat check` validates these exist.
- **Code refs**: `// @lat: [[section-id]]` (JS/TS/Rust/Go/C/PHP) or `# @lat: [[section-id]]` (Python/PHP) — ties source code to concepts

# Test specs

Key tests can be described as sections in `lat.md/` files (e.g. `tests.md`). Add frontmatter to require that every leaf section is referenced by a `// @lat:` or `# @lat:` comment in test code:

```markdown
---
lat:
  require-code-mention: true
---
# Tests

Authentication and authorization test specifications.

## User login

Verify credential validation and error handling for the login endpoint.

### Rejects expired tokens
Tokens past their expiry timestamp are rejected with 401, even if otherwise valid.

### Handles missing password
Login request without a password field returns 400 with a descriptive error.
```

Every section MUST have a description — at least one sentence explaining what the test verifies and why. Empty sections with just a heading are not acceptable. (This is a specific case of the general leading paragraph rule below.)

Each test in code should reference its spec with exactly one comment placed next to the relevant test — not at the top of the file:

```python
# @lat: [[tests#User login#Rejects expired tokens]]
def test_rejects_expired_tokens():
    ...

# @lat: [[tests#User login#Handles missing password]]
def test_handles_missing_password():
    ...
```

Do not duplicate refs. One `@lat:` comment per spec section, placed at the test that covers it. `lat check` will flag any spec section not covered by a code reference, and any code reference pointing to a nonexistent section.

# Section structure

Concise opening paragraphs give every section a stable overview for validation and discovery.

Every section in `lat.md/` **must** have a leading paragraph — at least one sentence immediately after the heading, before any child headings or other block content. The first paragraph must be ≤250 characters (excluding `[[wiki link]]` content). This paragraph serves as the section's overview and is used in search results, command output, and RAG context — keeping it concise guarantees the section's essence is always captured.

```markdown
# Good Section

Brief overview of what this section documents and why it matters.

More detail can go in subsequent paragraphs, code blocks, or lists.

## Child heading

Details about this child topic.
```

```markdown
# Bad Section

## Child heading

Details about this child topic.
```

The second example is invalid because `Bad Section` has no leading paragraph. `lat check` validates this rule and reports errors for missing or overly long leading paragraphs.
%% lat:end %%

%% lat-fork:begin %%
# lat.md conventions this project enforces

`lat check` fails on the first three rules below. The last two it cannot see,
and they matter as much. None of the five are style preferences. This block is
generated and a later `lat init` replaces it — record project guidance in
`lat.md/`, never here.

## Every document goes in a Diátaxis mode directory

A document belongs in exactly one of four subdirectories, and `lat check mode`
enforces one shape rule for each:

| Directory | Holds | Shape rule |
| --- | --- | --- |
| `lat.md/tutorials/` | a guided first pass for someone new | an ordered list of steps, and a stated outcome |
| `lat.md/how-to/` | a recipe for a task that recurs | an ordered list of steps |
| `lat.md/reference/` | lookup facts: fields, states, limits, names | no narrative prose — no second paragraph under a heading |
| `lat.md/explanation/` | why the design is what it is | no imperative commands |

A document is classified either by the directory it sits in, or by declaring
the mode in its own frontmatter:

```markdown
---
lat:
  mode: explanation
---
```

Both are enforced identically — `lat check mode` applies the shape rule to any
document that declares a mode, whether or not the root index carries
`require-mode: true`. That flag adds a separate rule: a document declaring *no*
mode, in no mode directory, becomes an error too.

Prefer the directory in a tree you own outright. Prefer the declaration when
the file cannot move — a document another project maintains, or a tree other
agents are writing to while you work. Moving costs every reference to the file;
declaring costs nothing at read time, because frontmatter sits above the first
heading and outside every section.

**A document that fails its mode is usually two documents.** A file that lists
the states *and* argues for the design is mixed: the lookup half goes in
`reference/`, the reasoning half in `explanation/`, and each links the other.
Filing it under one mode and softening the prose until the check passes is the
wrong repair.

Classifying a mixed document does not make it pass. Narrative prose put under
`reference/` fails on contact, because a reference may not carry a second
paragraph under a heading — so a move is not a way to adopt the rule cheaply.
Split first, then place. And `explanation` is not the safe default: it bans
only imperative commands, so nearly any prose passes it. Declaring it is a
claim about the document, not somewhere to put whatever is left over. A
document you cannot honestly classify is better left undeclared than
mislabelled.

Classify before writing, not after. If a `diataxis` skill is available, use it.

## Every project has at least one `@lat:` code ref

`lat check` fails a tree that has documents and no `@lat:` ref anywhere in the
codebase. A graph nothing points at cannot be reached from the code, which is
the only reason it exists.

Start at the application entrypoint — `config/application.rb`, `src/index.ts`,
`main.go`, `manage.py`, whatever a new reader opens first — and point it at the
root index:

```ruby
# @lat: [[lat#Acme]]
module Acme
```

Then one ref per section that source code actually implements, placed at that
code. Never in a block at the top of a file.

### An `@lat:` pointer is exempt from this project's comment conventions

A repository that minimises, budgets, or forbids comments is right about prose
comments and does not reach this one. An `@lat:` line is a machine directive,
in the same class as `# frozen_string_literal:` or `// eslint-disable`. It
carries no rationale, asserts nothing a reader could dispute, and cannot rot
quietly — `lat check` fails the moment its target moves or disappears.

Add the ref. Then, if the reasoning that would have been a comment is worth
keeping, put it in a `lat.md/explanation/` section and let the pointer reach it.

### The marker is a comment syntax, not a language allowlist

`//` for C-family languages; `#` for Ruby, Python, shell, Elixir, YAML, Make,
and everything else that comments with `#`. The scan is textual and walks every
non-markdown file in the project, so every language works.

Any list of example languages you find is a list of examples. Never conclude a
language is unsupported because it is absent from one. `lat check` prints what
it scanned:

```
Scanned 41 .md, 622 .rb, 118 .tsx in 1.2s
```

Read that line rather than guessing, and if you are still unsure, add one ref
and run the check. It costs one command.

(The tree-sitter grammars limit only `[[src/file.ts#symbol]]` wiki links, which
resolve a symbol inside source. `@lat:` refs point the other way and have no
such limit.)

## Test specs are wired to their tests

A document describing tests declares it in frontmatter:

```markdown
---
lat:
  require-code-mention: true
---
```

Every leaf section then needs exactly one `@lat:` comment at the test that
covers it, and every section needs at least one sentence saying what it
verifies and why. `lat check` reports any spec section no test claims, and any
ref pointing at no section.

## One specialty per document

A document is **small**, **discrete**, and does **not conflict** with any
other. Those are three demands on the same thing: a reader must be able to
find the one place a fact is written down, and trust it.

**Small — a document covers one specialty.** Not one topic area; one
specialty. When a document covers two, it is two documents. Past roughly forty
sections it has almost certainly become several, and an agent then loads all of
it to reach one part.

**Discrete — each document covers its own specialty.** Before writing a new
document, search for the specialty first:

```
lat search "the thing you are about to document"
```

An overlap has two honest repairs, and picking neither is what produces the
third copy. Either the two are one document and belong merged, or the part they
share is its own document that both link. Deciding they are "mostly different"
and writing anyway is how the set rots.

**Does not conflict — two documents never say different things about the same
specialty.** Never restate a fact another document owns. Link to it with
`[[section]]`. A restatement is a second copy, a second copy drifts, and drift
is how document B ends up contradicting document A while both look maintained.

The mode rule above is the sharpest available test of "one specialty": a
document that fails its mode is usually two documents. Split it. Do not soften
the prose until the check passes.

## Read sections, not files

`lat search` prints a section id and the exact lines that section occupies.
Resolve it with `lat section`, or read only that line range. Opening the whole
file is the reflex to break, and it is the expensive one:

```
lat search "how does backend selection work"
lat section "cli#CLI#search#Backend selection"
```

not a `read` of `lat.md/cli.md`. Measured on lat.md's own graph, the section
costs 4 KB against the file's 44 KB — eleven times the context for the same
answer, and the answer arrives buried in forty-one sections that were not
asked about.

Use `lat expand` on a prompt carrying `[[refs]]` for the same reason: it
resolves each ref to a location and a preview rather than to a file.
%% lat-fork:end %%
