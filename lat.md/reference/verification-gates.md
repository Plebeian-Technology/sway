---
lat:
  mode: reference
---
# Verification gates

`dip run verify` is the single gate that decides whether the tree is green. It runs fifteen lanes concurrently — eleven on the host, four in Docker — and writes each result to `tmp/verify/summary.json`.

## Exit codes

The script takes no arguments and refuses them.

- `0` — every lane green
- `1` — a lane failed, or the [[verification-gates#Onboarding coverage gate|onboarding coverage check]] failed
- `2` — a lane did not complete

## How lane durations are measured

The `seconds` a lane reports in `summary.json` runs from its start to the moment its own process exited, stamped by the lane's wrapper rather than read when the join loop reaches it.

- Every lane is started in one loop and joined in one loop, both in declaration order; `wait` on a pid that has already exited returns at once with its stored exit code
- Read at join time instead, a duration would be the join's clock, not the lane's: a lane joined behind a slow one would report that one's duration, and shard counts are chosen by comparing these numbers
- A lane killed before its wrapper's trailing lines ran leaves no stamp; the join's own clock is the fallback, and such a lane is classified did-not-complete on its exit code anyway

## RSpec runtime contracts

The Rails helper configures isolated test data, HTTP access, coverage and browser transport for both focused runs and the full gate.

- [[spec/support/live_llm_gate.rb#LiveLlmGate|LiveLlmGate]] applies WebMock permissions and VCR exclusions together. Only RUN_LIVE_LLM_TESTS=1 permits Anthropic and OpenRouter HTTP; credentials alone grant no network access. Localhost and local error collectors remain reachable. Anthropic live token checks use a fifteen-second timeout; OpenRouter uses its configured adapter timeout.
- SimpleCov starts before the Rails environment loads, so files loaded at boot or by eager loading under `CI` are measured; it records line and branch coverage. Its cover limits reporting to models, services, jobs, channels and controllers, plus the onboarding files [[config/onboarding_coverage_floor.yml]] lists. track_files adds unloaded files without excluding unrelated loaded files, which changes the denominator between browser and unit runs. Mailers remain outside the coverage glob. Command names include lane and worker to prevent concurrent reports from overwriting each other.
- Application tables are emptied before the suite and after system examples. System examples disable transactional fixtures because Puma-thread writes can escape the example transaction; other examples retain transactional cleanup. Schema and migration metadata are preserved.
- Examples restore User::ADMIN_PHONES and User::API_USER_PHONES after temporary overrides so an admin fixture cannot grant access in another example.
- Capybara uses ordinary Puma threading; rails_vite does not require the old single-thread restriction for directory changes. The server suppresses deployment config loading with config_files set to a dash, avoiding unused cluster hooks.
- Capybara leaves its server port unset so the OS selects an available port for concurrent checkouts. Non-production WebAuthn origins follow the request host and port; passkey tests do not require a fixed port.
- Examples run in randomized order with config.order = :random and Kernel.srand config.seed, ensuring reproducible example sequences and pseudo-random test data under --seed <seed>.

## Host lanes

Eleven lanes run directly on the host, needing no database.

- `rubocop` — Standard Ruby, via `bin/rubocop`
- `vitest` — frontend unit and component tests, worker pool capped, with the [[verification-gates#Frontend onboarding coverage gate|onboarding coverage floors]] enforced
- `tsc` — TypeScript types, excluding `mobile/`; rejects imports under `app/frontend/legacy/` as unresolved modules because that directory is absent, so no dedicated guard is needed
- `oxlint` — JS/TS lint, config `.oxlintrc.json`
- `oxfmt` — JS/TS formatting
- `mobile-jest` — mobile app tests, `TZ=UTC`, worker pool capped, with the [[verification-gates#Mobile onboarding coverage gate|onboarding coverage floors]] enforced
- `mobile-tsc` — mobile TypeScript, its own tsconfig and React Native types
- `mobile-oxlint` — mobile lint, its own `.oxlintrc.json`
- `brakeman` — Rails static security analysis
- `rbs-validate` — RBS signature validation
- `steep` — the RBS type check, via `dip run steep`: steep at information severity, no compose service behind it; declared last in the lane table, the slot it had as a Docker lane, so the summary order does not move
- `SWAY_VERIFY_JS_WORKERS` — the `--maxWorkers` both JS lanes are given, default `2`; `0` or `uncapped` passes no flag, which restores each pool's own default of roughly cores-1

## Docker lanes

Four lanes run inside the dip images. Each rspec worker gets its own SQLite file on a RAM filesystem, and the frontend is built once per run into its own directory, so concurrent runs cannot corrupt each other.

- `rake-gates` — the `sway:lint:*` rake gates: `admin_guards`, `org_admin_guards`, `inertia_matchers`, `env_reads`, `migration_models`, `inertia_prop_cache`, `param_names` and `rspec_constants`. `scripts/dip/rake-gates.sh` gives each one its own rake process and prints its own exit code, because each of them ends the process with `abort` on failure and would otherwise cancel the gates beside it. None of them writes to the test database, so the lane needs no database isolation of its own. `summary.json` carries the lane's `checks_ran` and `checks_failed`, read from that summary line, so a failed gate and a lane that ran no gate at all are told apart in the JSON rather than only in the log; a lane reporting `checks_ran: 0` is `did-not-complete`, never green
- `rspec-browser` — sharded Capybara and Selenium system specs
- `rspec-nonbrowser` — the sharded remainder of the backend suite
- `tessdata-parity` — Tesseract data parity
- `SWAY_VERIFY_BROWSER_SHARDS` — the shard count the `rspec-browser` lane is given, default `2`; a value that is not a positive integer is refused with exit `64` before any lane starts ([[verification-gates#Shard counts|why these defaults]])
- `SWAY_VERIFY_NONBROWSER_SHARDS` — the same for `rspec-nonbrowser`, default `4`

## Shard counts

Each rspec lane splits its examples across a fixed number of `parallel_tests` workers, one SQLite file each; the counts default to 2 browser and 4 non-browser shards and are set per run by two environment variables.

- `SWAY_VERIFY_BROWSER_SHARDS` — default `2`; `SWAY_VERIFY_NONBROWSER_SHARDS` — default `4`; each must be a positive integer, and any other value is refused before a lane starts with exit `64`, the code an argument earns
- The resolved numbers become the `N` in `sway:test:lane[browser,N]` and `sway:test:lane[nonbrowser,N]`, in the lane commands and in the printed reruns alike; `lib/tasks/sway_test_shards.rake` turns each into that many `parallel_rspec` workers with one SQLite file apiece
- 2 and 4 are the CPU-budget setting: larger counts finish the rspec lanes sooner but oversubscribe the CPU beside the host lanes, and at 2 and 4 rspec is not the critical path
- Larger counts are the faster setting for a quiet machine; gains flatten once one slow spec file sets the floor of a shard, and memory has not constrained the counts
- The rspec compose service carries no `cpus:` cap: a hard cap starves Selenium and turns browser examples into timeouts, whereas fewer shards means fewer processes contending

## Focused runs

The gate is the authority, but focused commands stay useful while working.

- `dip run rspec` — the full backend suite; takes no arguments
- `dip run bundle exec rspec spec/path_spec.rb:42` — a single example
- `dip run bundle exec rspec spec/path_spec.rb --seed 12345` — reproduce a specific randomized execution order
- `dip run vitest` — runs on the host, because the image's Node is not the pinned one; takes file paths
- `dip run steep` — steep on the host, the same check the gate's `steep` lane runs; no database
- `bin/steep check --severity-level=information` — the same check as `dip run steep`, for a container or CI where dip is absent; runs a local, untracked `bin/steep-rs-<os>` build when one is present and enforces its exit status; otherwise runs `bundle exec steep` as an advisory check that always exits 0 (`SWAY_STEEP_STRICT=1` enforces it), slower by minutes and with known disagreements tracked in steep-rs; no database
- `pnpm lint`, `pnpm fmt:check`, `npx tsc`, `bin/rubocop` — no database, host-runnable

## The frontend test bundle a spec run reads

Every page a request or system spec renders reads the manifest under `public/vite-test`, so a stale bundle fails in ways that look like application defects.

- `.dockerdev/entrypoint.sh` is the entrypoint of the `rails` and `rspec` services and rebuilds the bundle when, and only when, the frontend has changed
- The check runs whenever an invocation names `rspec`, which covers `dip run rspec`, `dip run bundle exec rspec spec/path_spec.rb` and a bare `docker compose run rspec bundle exec rspec …` — the focused form replaces the compose command, so a command-line build step could not cover it
- `scripts/dip/vite-test-build.sh hash` reads `app/frontend`, `package.json`, `pnpm-lock.yaml`, `vite.config.ts`, both tsconfigs and `config/vite.json` if it exists, and hashes each file's path together with its contents
- Paths are in the hash, not only contents: over contents alone, adding or deleting a zero-byte file left the hash byte-identical, so a bundle built from a different set of files read as unchanged. With paths, an addition, a deletion and a rename each move it
- The hash is stamped into `.frontend-inputs` inside the build directory after a successful build, so `SWAY_VITE_BUILD_DIR` gives each run its own stamp as well as its own bundle
- A failed build stops the run before rspec starts, which is what the old `&&` in the compose command guaranteed
- Anything not naming `rspec` — `dip run rails c`, the two `sway:test:lane` rake lanes, an explicit `pnpm vite build` — passes straight through, so nothing builds twice
- With `SWAY_VITE_BUILD_DIR` unset the entrypoint invents `vite-test/run-adhoc-<container>` and exports it, so no run ever builds into `public/vite-test` itself. Vite empties its output directory first, and that directory is the parent of every run's own, so a build there would delete a live run's whole bundle
- `scripts/dip/rspec.sh` and `scripts/dip/verify.sh` both sweep `run-*` directories older than a day before they start, which is what keeps the volume from filling with abandoned bundles
- `RailsVite.config.auto_build` is disabled in test (`config/initializers/_vite_build_dir.rb`) because the bundle is pre-built; an in-process build during a request empties the output directory, racing with concurrent readers
- The leading underscore on `config/initializers/_vite_build_dir.rb` ensures it sorts and runs before initializers like `inertia.rb` and `content_security_policy.rb` that read the manifest at boot

## What a printed rerun does and does not reproduce

Each red lane prints a copy-pasteable rerun beside its log path. Every Docker lane's rerun is built from the same variables its invocation passes, so pasting one reproduces the lane's configuration rather than a quieter one.

- No `--name`, so a pasted rerun cannot collide with a container the run has already cleaned up
- `SWAY_TEST_DATABASE_DIR=/testdb` — the worker databases live on a RAM filesystem; without it the rerun writes into the shared storage volume and can contend with a neighbour
- `SWAY_VITE_BUILD_DIR` — this run's own frontend build; without it the rerun reads the shared `public/vite-test`, which may hold a stale build or another run's
- `SWAY_TEST_LANE` — names the coverage slice; without it the two rspec lanes' slices overwrite each other
- `SWAY_VERIFY_RUN_ID` — run attribution
- `SWAY_REQUIRE_BROWSER=1` on the browser lane — without it a machine with no Chrome skips every browser example and answers green, the outcome that flag exists to prevent
- `dip compose run` re-splits an already-glued argument line, so every rerun carrying a `-e` flag or a `sway:test:lane[...]` argument uses `docker compose` directly
- Not reproducible outside `verify.sh`: the error collector. `scripts/dip/rustrak.sh` starts it and exports `RUSTRAK_DSN` and `VITE_RUSTRAK_DSN` for the whole run, and `--no-deps` stops compose starting it, so an example that needs the collector skips in a rerun. The printed report says so, because a skip read as a pass is how a real red becomes "cannot reproduce, must be flaky"

## What the pre-commit hook checks

`.husky/pre-commit` runs project-wide type checking and formatting on every commit, plus the checks listed below.

- `oxlint` over the project when any non-`mobile/` file is staged; mobile-only or deletion-only commits skip it
- `tsc` over the root tsconfig, which excludes `mobile/` through its own include block, on every commit
- `oxfmt` over the project in write mode on every commit
- `rubocop --force-exclusion --autocorrect` over the staged Ruby files, safe cops only, followed by `git update-index --again`, which re-stages whole files
- A literal-value check on each staged `.kamal/secrets*` file, then `gitleaks` over the staged index on every commit
- Vitest does not run in this hook

## Onboarding coverage gate

`sway:coverage:onboarding` fails when any onboarding file listed in [[config/onboarding_coverage_floor.yml]] is under its line or branch floor, or is absent from the coverage report; the target for every file is 100 percent line and branch coverage.

- [[lib/onboarding_coverage_check.rb#OnboardingCoverageCheck]] merges the per-worker results in `coverage/.resultset.json` with SimpleCov's own result merger and scores each listed file with SimpleCov's own source-file statistics, so its numbers match the HTML report
- `dip run verify` runs the task in its own container once both rspec lanes are green, passing the run's start time so only this run's worker results are merged; it prints every file's numbers under `onboarding coverage:` after the lane table, and a red check makes the run exit `1`. The check is not a lane and is absent from `summary.json`
- CI runs the task after the rspec step in `.github/workflows/rspec.yml`, where the one fresh worker result is the whole report
- Each floor is the percentage measured on the commit that set it, rounded down to one decimal place
- Raising a floor: measure the file after the change that adds coverage, then write the new percentage, rounded down to one decimal place, into the floor file in the same commit; a floor is never lowered to make a run pass
- A line no test can reach, such as the `return nil unless change` guard in [[app/services/user_address_switch_service.rb]], keeps its file under 100 percent until the line is removed; sub-100 entries in [[config/onboarding_coverage_floor.yml]] document the unreachable line or branch in an adjacent YAML `#` comment
- `config/initializers/monkey_patches.rb` is not listed: SimpleCov's `rails` profile skips everything under `config/`, so the file can never appear in the report
- Worker results from another rspec run in the same checkout while `verify` runs are merged too; they can only raise a file's numbers, never lower them

## Frontend onboarding coverage gate

The full vitest run fails when any frontend onboarding file in [[config/onboarding_coverage_floor.frontend.json]] is under its line or branch floor; the target for every file is 100 percent line and branch coverage.

- [[vitest.config.ts]] builds one per-file threshold from each entry of the floor file and limits coverage to those files; coverage is not enabled by default, so `dip run vitest <file>` reports none and a partial run never trips a threshold
- The `vitest` lane of `dip run verify` and the test step of `.github/workflows/vitest.yml` pass `--coverage`; a red lane names the file and the metric under its floor
- The floor file is separate from [[config/onboarding_coverage_floor.yml]] so the Ruby checker never reads it
- Each floor is the percentage measured on the commit that set it, rounded down to one decimal place
- Raising a floor: run `pnpm test --coverage`, read the file's line and branch columns, and write them, rounded down to one decimal place, into the floor file in the same commit as the tests; a floor is never lowered to make a run pass
- `app/frontend/__tests__/coverageFloors.test.ts` checks that the floor file lists exactly the onboarding files, that each exists, and that every percentage is between 0 and 100
- Provably unreachable branches holding an entry under 100.0 carry a `"reason"` field naming the unreachable line or guard

## Mobile onboarding coverage gate

The full mobile Jest run fails when any mobile onboarding file in [[config/onboarding_coverage_floor.mobile.json]] is under its line or branch floor or has no coverage data; the target for every file is 100 percent line and branch coverage.

- [[mobile/jest.config.js]] builds one per-file threshold from each entry of the floor file and limits coverage to those files; Jest collects coverage only when `--coverage` is passed, so `pnpm --dir mobile test <file>` reports none and a partial run never trips a threshold
- The `mobile-jest` lane of `dip run verify` and the Jest step of `.github/workflows/mobile-test.yml` pass `--coverage`; a red lane names the file under its floor
- A listed file that no test loads fails the run with `Coverage data for <file> was not found`
- Floor-file keys are repository-relative paths, as in the frontend floor file
- Each floor is the percentage measured on the commit that set it, rounded down to one decimal place
- Raising a floor: run `TZ=UTC pnpm --dir mobile exec jest --ci --forceExit --watchman=false --coverage`, read the file's line and branch columns, and write them, rounded down to one decimal place, into the floor file in the same commit as the tests; a floor is never lowered to make a run pass
- `mobile/__tests__/coverageFloors.test.ts` checks that the floor file lists exactly the onboarding files, that each exists, and that every percentage is between 0 and 100
- Provably unreachable lines or branches holding an entry under 100.0 carry a `"reason"` field naming the unreachable line or guard

## Known traps

Two environments produce misleading reds, one lane self-skips, and one lane reported green without checking anything.

- A worktree carries tracked files only, so `scripts/dip/secrets-root.sh` runs first; Rails credentials read as absent there, and [[run-the-stack#Git inside a worktree's container|git needs the mount that script writes]]
- `verify` can starve its own lanes under contention, so a red lane deserves a solo rerun before being believed
- [[.rubocop.yml]] excludes nested checkouts under `.worktrees/**/*` as well as `.claude/**/*`; directory exclusions ending in `/**/*` prune their dependency trees before target enumeration.
- System specs self-skip with a logged message when no Chrome or Chromium binary is found
- The rbs collection installs into `tmp/rbs-cache` through `XDG_CACHE_HOME` rather than `~/.cache/rbs`, which is not writable from every context this gate runs in
- From a linked worktree under `.claude/worktrees`, rubocop reads the main checkout's `.rubocop.yml` as an ancestor config as well as this checkout's, and that one's `AllCops.Exclude` holds `.claude/**/*` relative to the main root — so `--force-exclusion` drops every file named on the command line and the run reports `target_file_count: 0`, which reads exactly like a clean tree. `--ignore-parent-exclusion` and an explicit `--config` each fix it; `bin/rubocop` pins the config already, a bare `bundle exec rubocop` does not
- `node_modules` is untracked, so a worktree has none of it and any lane guarded on a binary under it skips without attempting anything; `git rev-parse --git-common-dir` names the main checkout's `.git` from inside a worktree, which is the way back to the install
- The container sweep's behavioural example needs a docker daemon, and no compose service mounts the docker socket, so it self-skips with a logged message inside the rspec container and runs for real on the host: `SWAY_ALLOW_HOST_RAILS=1 bundle exec rspec spec/scripts/dip_verify_cleanup_spec.rb`
- `/tmp` is mounted `noexec` in the rspec container, and bash walks past a stub it cannot execute to the real binary behind it on `PATH`, so a spec that shims a command puts the shim under `tmp/` instead
- A failed summary write is reported on stderr and does not stop the run: the lane table still prints and the run still exits with the code it computed, so a `2` (a lane did not complete) cannot collapse to a `1`
- `rbs-validate` passes `-I sig -I sig-test`; without those flags `rbs validate` loads no project signatures, prints nothing and exits 0 whatever `sig/` holds. It reports duplicate definitions [[rbs-signatures#Why this is not caught by the verification gate|as they arise]]
