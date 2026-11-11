# Operations

> **The addresses and account names are not in this file.** They describe one
> installation, and this repository is public. Commands below use the variable
> names from `deploy/config/sway.env` — copy `deploy/config/sway.env.example`,
> fill it in, then `set -a; . deploy/config/sway.env; set +a` before pasting
> any of them.
Operator documentation for Sway: recurring rake tasks, the daily
legislator-vote refresh, and recovery procedures. Moved here from the README,
which now targets newcomers.

Run rake tasks via `dip run rails <task>` (Docker dev) or `bin/rails <task>`
directly in production. List everything with `dip run rails -T sway` /
`dip run rails -T db:seed`.

## Rake Tasks

### Seeds & Data

- **`db:seed`** — Standard Rails seed (locales, legislators). Skips already-seeded rows. See `db/seeds.rb`.
- **`db:seed:bills`** — Seed Baltimore bills via the legislation pipeline (reuses on-disk cache).
- **`db:seed:bills:force`** — Reseed bills even if Baltimore already has some.
- **`db:seed:bills:refresh`** — Force the pipeline to re-fetch upstream data (Legistar API + hearing PDFs) before seeding.
- **`db:seed:force`** — Re-seed locales, legislators, and bills unconditionally (bypasses the out-of-band-edit guard).

### Legislators

- **`sway:assign_new_user_legislators`** — Deactivates all `UserLegislator` rows and reassigns each user to current legislators. Run after each election.
- **`sway:scores:recompute_all`** — Rebuilds every derived score row (`BillScore`, `BillScoreDistrict`, `LegislatorDistrictScore`, etc.) from existing votes. Deletes nothing and is safe to run again. Replaces the older `sway:backfill:legislator_locale_scores` task.

#### Refreshing legislator data

`db/seeds/data/**/legislators.json` (one file per locale: Congress, Maryland, Baltimore) is not hand-maintained — `RefreshLegislatorsCacheJob` re-pulls each locale's authoritative source (congress.gov, OpenStates, and a curated Baltimore roster respectively), writes back the merged JSON, uploads a timestamped copy to GCS, and opens one combined GitHub PR when anything actually changed.

- **Runs automatically** every Sunday at 3am UTC in production (`config/recurring.yml`).
- **Force a refresh by hand:**
    ```bash
    dip run rails runner 'RefreshLegislatorsCacheJob.perform_now(force: true)'
    ```
- **PRs land for ops review** — nothing auto-merges. Review the diff like any other PR before merging it in.
- Legislator turnover (a seat changing hands, a term ending) is handled automatically by the reconciliation system (`SeedLegislatorTerms`, `ReconcileUserDistrictsJob`), not by a manual deactivation task.

### Assets (Legislator / Org / Locale Photos)

- **`sway:assets:mirror_external_assets`** — Mirror external organization / sway_locale / legislator photo URLs into ActiveStorage (GCS in production, local Disk in dev).
- **`sway:assets:reset_photo_urls[locale]`** — Recovery for legislator rows left holding dead `localhost:3000` ActiveStorage proxy URLs after a volume wipe took the blobs behind them. The mirror service no longer rewrites `photo_url` to an internal proxy URL, so only rows poisoned earlier need this. Resets `legislators.photo_url` from seed JSON. Optional positional `locale` arg scopes to one `SwayLocale`. Set `FORCE=1` to reset every legislator (or every legislator in the locale) regardless of current value.
    ```bash
    dip run rails 'sway:assets:reset_photo_urls[baltimore-maryland-united_states]'
    dip run rails 'sway:assets:reset_photo_urls[baltimore-maryland-united_states]' FORCE=1
    ```

### Lint / CI

- **`sway:lint:admin_guards`** — enforces `before_action :verify_is_sway_admin` on every admin-gated controller. Fails CI if a controller in `lib/tasks/sway_lint.rake`'s allowlist drops the guard.
- **`type`** — Runs RBS validation then steep type checking (`bundle exec rbs -I sig -I sig-test validate`, then `bin/steep check --severity-level=information`).
- **`annotate_models` / `annotate_routes`** — Provided by `annotate_rb`; refresh schema/routes annotations in source files.

### Storage / Ops

- **`sway:volume_setup`** — Sets up a remote volume by downloading files from a Google Cloud bucket. Used during host bootstrap.
- **`fly:build` / `fly:release` / `fly:server`** — Legacy Fly.io deploy hooks (project now deploys via Kamal; kept for reference).

## Updating Legislator Votes on Legislation

Sway has a unified rake task that refreshes legislator-vote rows from the
upstream source for each locale (Congress → Congress.gov scraper; Maryland →
Open States / Maryland PDFs; Baltimore → Legistar via `Legistar::Client` in
the Ruby legislation pipeline).

```bash
# Refresh every bill across every locale (GLOBAL — Bill.all).
# NOTE: no-arg mode iterates EVERY Bill in EVERY locale via Bill.all.
# It is NOT locale-batched. For a single-locale refresh, pass the locale
# argument explicitly (see below).
dip run rails sway:legislator_votes:update

# Refresh only one locale's bills (locale arg is the canonical
# "city-state-country" name format — same as SwayLocale#name returns).
dip run rails 'sway:legislator_votes:update[baltimore-maryland-united_states]'
dip run rails 'sway:legislator_votes:update[maryland-maryland-united_states]'
dip run rails 'sway:legislator_votes:update[congress-congress-united_states]'
```

Behavior:

- **No-arg mode is GLOBAL.** `dip run rails sway:legislator_votes:update`
  (no argument) iterates every Bill across every locale via `Bill.all`. It
  is NOT locale-batched; it does NOT skip Baltimore or any other locale.
  For a scoped refresh, always pass the canonical `city-state-country`
  locale name.
- **Per-bill logging** — one log line per bill:
  `legislator_votes:update — ok bill_id=42 external_id=BAL-2024-001 locale=baltimore-maryland-united_states`
- **Collect-and-continue** — per-bill errors are logged + collected. The
  task exits non-zero at the end if any bill failed.
- **3-consecutive-error circuit breaker** — three consecutive failures
  abort the run.
- **No `FORCE` env var** — manual admin edits via the Bill Creator UI are
  sticky (`legislator_votes.source = "manual"`); the rake task and the
  daily sweep job both respect that flag and refuse to overwrite manual
  rows.
- **Bypasses the pipeline cache** — operator-triggered refreshes pass
  `force_refresh: true` internally so Baltimore bills always re-check
  Legistar, matching the daily sweep behavior.

The same code path runs automatically once per day at **4am EST** (9am UTC,
UTC-fixed cron — DST drift accepted) via `LegislatorVoteSweepJob`,
registered in `config/recurring.yml`. The sweep also passes
`force_refresh: true` to bypass the pipeline cache so the daily
run always re-checks upstream. Operators only need to invoke the rake task
for ad-hoc backfill or to scope a refresh to a single locale.

Event-driven entry points:

1. **`Vote#after_create`** — when an admin records a vote with a roll-call
   number (Congress/MD) the per-locale service runs inline; for Baltimore
   (`bill.sway_locale.local?`) it enqueues `LegislatorVoteFetchJob`.
2. **`Bill#after_commit on: :update`** — changes to whitelisted vote-trigger
   fields (`external_id`, `external_version`, `chamber`, `status`, and the
   `house_*`/`senate_*` vote_date_time fields) enqueue
   `LegislatorVoteFetchJob` for any locale.

Admin UI: when the Bill Creator (`BillsController#edit`) is reopened after
an automatic refresh, a one-time toast surfaces:
"Legislator votes refreshed at HH:MM from {source}." The
toast excludes manual rows so an admin's own ledger edits do not
self-toast.

## Cleaning Hearing Testimony Before the Positions Prompt

Baltimore hearing testimony arrives as one long bundle of forwarded emails.
Most of a well-attended bill's testimony is either a repeated IT warning
banner or copies of one campaign letter, and the model that drafts
organization positions has a limited amount of text it can read. The
`clean-testimony` pipeline stage runs between fetching testimony and
building that prompt. It splits the bundle into individual letters, repairs
characters the PDF-to-text extraction breaks, removes the repeated banner,
groups letters that reuse the same text, and judges what kind of source
each letter is — all before the positions call ever runs.

Run it from the Bill Creator's Pipeline & LLM tab, the same way as any other
pipeline stage. `Testimony::CleanAndGroupService` is the class that runs it;
`app/models/pipeline/stage_keys.rb` names its key, `clean-testimony`.

### What an operator sees

Two places on the Bill Creator show what the stage found:

- **The Summary tab**, beside the draft organization positions, states one
  fact in one sentence: how many letters reached the model against how many
  exist. If nothing was left out, the sentence says so. If something was,
  Approve is blocked until an operator acknowledges it — see "The
  acknowledgement gate" below.
- **The Pipeline & LLM tab**'s testimony report gives the full breakdown: a
  bar showing what reached the model, what was removed as repeated, and
  what was left out; a table of collapsed campaigns with their sender and
  letter counts; how many letters were read as individuals; and, if the
  operator pasted testimony in by hand, how much of the size limit that
  paste takes.

Three words on these two screens mean three different things, and the
screens never use them interchangeably:

- **Reached the model** — this text was in the prompt the positions call
  actually read.
- **Removed** — repeated text taken out on purpose (the IT banner, a
  campaign template's duplicate copies). Not a loss.
- **Left out** — this text did NOT reach the model, because the prompt hit
  its size limit. This is the only one of the three that means something
  was lost.

Every count on these screens is a whole number of characters or letters. A
missing count means the stage never measured that number — never a zero it
did not measure. A zero means the stage measured it and found none. The
campaign table renders a missing count as an em dash; other surfaces fall
back to different wording instead (the Summary tab's coverage notice, for
example, drops to raw-character-count copy rather than showing a dash).

### What the stage deliberately does not do

- **It never touches testimony an operator pasted in by hand.** Text typed
  or pasted into the Bill Creator's supplemental testimony field reaches the
  positions prompt exactly as saved — no character repair, no banner
  removal, no grouping. Only testimony extracted from hearing attachments
  is cleaned. The testimony report's "Your pasted testimony" block states
  this on screen, in the same words.
- **No count or threshold decides that a domain is a sending service.** The
  stage counts how many senders and letters a domain has carried; it never
  turns that count into a label by itself. `SetSendingServiceDomainLabelService`
  is the only place a "sending service" label is ever written, and it only
  ever records an operator's own confirm-or-remove decision, made on the
  Pipeline & LLM tab's sending-services panel.

### Re-running it

Re-run `clean-testimony` from the Pipeline & LLM tab against testimony
already fetched — nothing downloads again. Re-running is safe: it always
replaces the bill's stored cleaned result and each domain's per-bill counts,
never adds to them, so tuning the stage's own matching against one bill is
cheap to repeat.

**An acknowledgement is tied to the exact numbers shown, not to a run.**
`TestimonyCoverageAcknowledgement` is keyed on the bill and a digest of the
coverage numbers, so re-running with unchanged testimony reproduces the same
digest and the existing acknowledgement still applies — no need to
acknowledge again. Only a run that actually changes the numbers invalidates
it; approving an organization or campaign position then stays blocked until
the operator acknowledges the new numbers.

The per-bill size limit that decides how much testimony reaches the model
is `BillPositionsPromptBuilder::MAX_TESTIMONY_CHARS` — see that constant for
the current number and how it differs between development and production.
`Testimony::CoverageReport` is the one place every count on these two
screens is worked out; it reads that limit rather than each screen guessing
its own.

### The acknowledgement gate

Approve is blocked on the Summary tab whenever testimony was left out, or
the `clean-testimony` stage's last attempt failed, or it never ran on this
bill at all. All three mean the same thing: a claim about which
organizations testified could rest on evidence the operator was never
shown. The blocked notice names how many letters were left out and why.

Clicking "Acknowledge the missing testimony" records who acknowledged it
and when, tied to the exact numbers shown at that moment. Approve unblocks
immediately, with no page reload. Reject and Edit are never blocked by this
gate — neither one publishes anything.

## The Machines

Sway is built to run on one small host — the reference setup is a single-board
ARM computer with a plugged-in SSD — with an optional second machine as a
standby.

| setting | what it names |
| --- | --- |
| `SWAY_HOST` | the deploy target: the machine serving the public |
| `SWAY_STANDBY_HOST` | optional: a second machine that keeps a daily restored copy of the database (see `docs/litestream-restore.md`) |

Both live in `deploy/config/sway.env` (copied from
`deploy/config/sway.env.example`, ignored by git), and `config/deploy.yml`
reads them through `SwayDeployConfig`. **Which machine a deploy goes to is
written in exactly one place**; a test fails if an address appears anywhere
else in the deploy config.

Every value can be overridden as an ordinary environment variable, so a single
command can act on the other machine without editing anything:

```bash
SWAY_HOST=$SWAY_STANDBY_HOST SWAY_STORAGE_DIR=$SWAY_STORAGE_DIR kamal app containers
```

Leaving the variables out uses the machine named in `sway.env`. That is what
makes rolling a switch-over back cheap — it is a prefix on one command, not an
edit. Moving production to a different machine is its own runbook:
`lat.md/how-to/move-to-a-new-host.md`.

The same values decide where `scripts/provision-litestream-key.sh` sends the
backup credential, so the copying service follows the app rather than being
remembered separately.

### Where the app image comes from

Deploys build the image on your workstation and upload it to the image
registry named by `$SWAY_REGISTRY`. A registry without authentication or TLS
is only safe on a network you trust; set the registry credentials in
`.kamal/secrets-common` and `config/deploy.yml` to match yours.

A plain HTTP registry has a cost: Docker refuses plain HTTP unless told the address is
trusted, and it says so confusingly —

```
http: server gave HTTP response to HTTPS client
```

which blames encryption when the real answer is "this machine was never told to
allow it". Every machine that uploads or downloads needs the address listed:

- **Linux hosts** — `/etc/docker/daemon.json`, then `sudo systemctl reload docker`
  (reload, not restart — nothing running has to stop)
- **a macOS workstation** — whichever engine is actually running. If that is
  OrbStack, the file is `~/.orbstack/config/docker.json`; `~/.docker/daemon.json`
  belongs to Docker Desktop and OrbStack never reads it. Check what the running
  engine believes rather than what a file says:
  `docker info --format '{{json .RegistryConfig.IndexConfigs}}'`

`scripts/migrate-registry.sh` moves the store between machines and refuses to
switch until the machine losing it can still reach it by name.

### The storage folder

Everything that must survive a deploy lives in one folder on the host's
plugged-in drive (`SWAY_STORAGE_DIR`), bound into the container at
`/rails/storage`: the SQLite databases, the downloaded seed and map files, and
uploaded images.

**It must be owned by the container's user before the first deploy.** The
container runs as uid 100, gid 101, and a bind-mounted folder keeps the host's
ownership, so a folder made by anyone else is read-only to the app:

```bash
sudo chown -R 100:101 $SWAY_STORAGE_DIR
sudo chmod 755 $SWAY_STORAGE_DIR
```

Skip it and the deploy fails ten minutes later saying only that the container
never became healthy, with `Permission denied @ dir_s_mkdir` buried in its log.

Listing the folder afterwards may show the owner by local names rather than
numbers — on Debian-based systems, including Raspberry Pi OS, **`messagebus
crontab`**. That is right: those are the host's names for user 100 and group
101. Check with `ls -ln`.

### How traffic reaches it, and how a switch-over works

Nothing is exposed to the internet directly. A Cloudflare tunnel runs *on the
serving host* and dials out, so **whichever machine runs the tunnel is the
machine the public reaches.** That makes it the switch-over lever: stop the
tunnel on the old machine, start it on the new one, and traffic follows.
Rolling back is the same move in reverse.

The tunnel is a Kamal accessory, so ordinary `kamal deploy` leaves it alone; it
only moves when asked explicitly.

### Copies of the data

Two independent things, and both are wanted:

- **Litestream** replicates the database to cloud storage continuously, so the
  most that can be lost is the seconds since the last write shipped. It runs as
  an accessory alongside the app.
- **A whole-file backup** is taken once per deploy before migrations run, which
  is the copy you want when a migration is what went wrong. `BootBackupGuard`
  keeps it to one per deploy so a crash-looping container cannot fill the bucket.

Restoring is written up in [docs/litestream-restore.md](/docs/litestream-restore.md).

## Local Error Collector (development and test only)

Rustrak runs beside the dev stack and receives browser and Ruby errors, so a
broken page leaves a record instead of one console line. It never runs in
production or CI, and production still reports to Sentry.

`dip run dev` sets all of it up. No manual step and no `.env` file are needed.
On first run `scripts/dip/dev.sh` writes four gitignored files under `config/`:

| File | What it is |
| --- | --- |
| `rustrak_session.key` | Signs dashboard cookies. The collector refuses to start without one. |
| `rustrak_admin.key` | The dashboard login, as `email:password`. |
| `rustrak_project.key` | Where errors are sent. `bin/rustrak-provision` asks the collector for it. |
| `rustrak_mcp.key` | API token for the MCP server. `bin/rustrak-mcp-token` asks for it. |

Read the dashboard login with `cat config/rustrak_admin.key`.

Every one of those steps stops early when its file is already there, so a
restart changes nothing. Delete a file to have it made again.

Set `RUSTRAK_SUPERUSER` yourself before the first start to choose your own
login. It can only be set once: the collector reads it while it has no users,
sign-up is invite-only and always refused, and there is no password reset. On
every later start the collector logs that it already has users and skips this
— that line is expected.

| What | Where |
| --- | --- |
| Dashboard | <http://127.0.0.1:8483> |
| Collector API | <http://127.0.0.1:8482> |
| Database | Docker named volume `sway_rustrak_data` |

Both ports are published on loopback only, so nothing off this machine can
reach either one.

### Where the addresses come from

`config/rustrak_project.key` holds one address, the one a browser on the host
uses. The start-up scripts read it and export two, because the same project is
reached by two different routes. `scripts/dip/rustrak.sh` holds that logic once,
and `dev.sh` and `rspec.sh` both call it.

Which route a value needs depends on where the reporting thing **runs**, not on
what it is:

```
# dip run dev — the browser is on the host, Rails is in a container
VITE_RUSTRAK_DSN=http://<public-key>@localhost:8482/1   # published port
RUSTRAK_DSN=http://<public-key>@rustrak:8080/1          # container network

# dip run rspec — Rails AND Chromium are both in the container
VITE_RUSTRAK_DSN=http://<public-key>@rustrak:8080/1
RUSTRAK_DSN=http://<public-key>@rustrak:8080/1
```

Getting the second pair wrong is the easy mistake: `localhost` inside the test
container means the container itself, so every report is refused with nothing
to see.

Do not put either in `.env.development` or `.env.test`. `.dockerdev/compose.yml`
declares both, and a value there wins over `env_file`, so a copy in an env file
is ignored and only misleads the next reader. That is why `dip run rspec` runs a
host script rather than a container service: the addresses have to be in the
environment of whatever calls `dip compose`.

Without an address both SDKs stay off and nothing breaks. An address already in
the environment wins over the provisioned one, and an empty address counts as
an address, so that is how to aim the app elsewhere or switch it off:

```bash
RUSTRAK_DSN= VITE_RUSTRAK_DSN= dip run dev
RUSTRAK_DSN= VITE_RUSTRAK_DSN= dip run rspec
```

A DSN pointing anywhere but this machine is refused rather than used, in both
the browser and Ruby. That is deliberate: a copied `.env` is otherwise all it
takes to start sending real testimony somewhere else.

### What a test run records

`dip run rspec` reports the same errors production would. Two kinds of red, and
only one of them is the app breaking:

| What went wrong | Recorded? |
| --- | --- |
| An expectation did not hold | No. RSpec caught it; the app never saw it. |
| An error escaped into the example | Yes. Nobody caught it, so it is an application error. |
| The app caught an error and reported it itself | Yes, exactly as in production. |

Every event carries an `rspec.example` tag naming the file and line of the test
that produced it, so you can tell a deliberate error-path test from a surprise
without reading the stack.

**The cost:** a test that drives an error path on purpose leaves a record and
still passes. That is accepted. An error the app chose to report is worth
seeing, and the tag makes the deliberate ones easy to filter out.

`dip run rspec` takes no arguments and refuses them rather than ignoring them.
For one file or one example use `dip run bundle exec rspec spec/path_spec.rb:42`,
which reports nothing — it does not go through the script.

### The mobile app

`mobile/` reports to the same collector in development, and never to Sentry.
`mise.toml` exports `RUSTRAK_DSN_MOBILE` from the same
`config/rustrak_project.key`, and `app.config.ts` passes it to the app. Start
Expo from inside the repo so mise has exported it.

This reaches the **iOS simulator and the Android emulator only**. The simulator
shares the host's loopback, and the emulator reaches its host as `10.0.2.2`,
which the app substitutes for `localhost` on Android.

A physical phone cannot reach the collector, and that is the intended limit.
Letting one in means binding the collector past loopback onto the network,
where anything on that network could read an error store holding real
testimony.

On a phone the address reads `localhost`, which is the phone itself, so the
guard accepts it, the SDK starts, and the reports go nowhere. Nothing is
recorded and nothing leaves the device. The warning about physical devices
only appears for an address that is not loopback at all.

Mobile tests are Jest, with no app and no network, so nothing is reported from
them. The console-capture half has no mobile equivalent.

### Reading the errors from an AI assistant

The collector ships an MCP server, so an assistant can query the errors
instead of a person reading the dashboard. Declare it in your own untracked
`.mcp.json` (command `npx -y @rustrak/mcp`, with `RUSTRAK_API_URL` set to
`http://127.0.0.1:8482` and `RUSTRAK_API_TOKEN` set to `${RUSTRAK_API_TOKEN}`);
`dip run dev` already made the token.

`mise.toml` reads `config/rustrak_mcp.key` and exports `RUSTRAK_API_TOKEN`,
so no file holds the token. Open a new shell, then restart the assistant. MCP servers
connect at start-up.

Run `bin/rustrak-mcp-token` by hand only after deleting the file, to replace
the token.

Without the token the server exits and reports as failed. That is deliberate.
A failed server is visible, and a silent one is not.

The server has 64 tools, and 14 of them write. It cannot make an alert channel:
it has `list_alert_channels`, `list_alert_rules` and `test_alert_channel`, and
no create. An alert channel is the collector's only route off this machine, so
that limit matters.

### Clearing it out

Nothing in Rustrak prunes, and it has no retention setting, so the database
grows for as long as it is left alone. It holds nothing that is not
reproducible, so throw it away when it gets large:

```bash
dip down
docker volume rm sway_rustrak_data
dip run dev
```

This deletes the projects too, so the DSN in `.env.development` stops matching
and must be replaced with the new project's. The dashboard login survives:
`config/rustrak_admin.key` is on disk, and an empty database lets the collector
read it again.

### What it does and does not protect

Both SDKs scrub emails, phone numbers and Anthropic keys before sending, and
send no request bodies, headers, cookies or local variables. A street address
written as prose is not findable by any pattern and is not scrubbed — what
keeps testimony out is that the collector runs on the same host and has no
outbound path. Do not configure an alert channel or SMTP: those are the only
ways the collector can talk to anything.

## Environment Variables

Every setting a running Sway reads from its environment is declared once in
`lib/sway/settings/<group>.rb` and read through `Sway::Settings`, never from
`ENV` directly (see `CLAUDE.md`'s "Environment Variables" section). A new
checkout needs no `.env.development` or `.env.test` to boot: the declared
settings that are not required carry defaults.

The stand-in account `SkipPhoneVerificationProvisioner` builds when phone
verification is skipped has two settings. `DEV_ACCOUNT_FULL_NAME` is the name on
the account. `DEV_ACCOUNT_SWAY_LOCALE` is a locale's computed name: its city,
region and country joined by hyphens, as in `baltimore-maryland-united_states`,
which is also the default.

The account's address comes from the jurisdiction, not the environment. A
`sway_locales` row carries `sample_street`, `sample_postal_code`,
`sample_latitude` and `sample_longitude`; `db:seed` puts an address on the
Baltimore row, and the `/admin/locales` page edits all four on any locale
without a deploy. The stand-in sign-in therefore needs seed data: if the locale
`DEV_ACCOUNT_SWAY_LOCALE` names does not exist, or exists with no sample
address, the flow raises an error naming that locale and the blank columns
instead of building an account with no district. Production locales carry no
sample address and never run this path.

`RUSTRAK_DSN` and `VITE_RUSTRAK_DSN` point the application and the browser at
the local error collector. Set them in `.env.test` and `.env.development` as the
tracked example files show, or the collector stays silent. See "Local Error
Collector" above.

## See Also

- [docs/kamal-secrets.md](/docs/kamal-secrets.md) — production secrets via Kamal + Bitwarden
- [docs/secret-scanning.md](/docs/secret-scanning.md) — gitleaks / trufflehog gates
