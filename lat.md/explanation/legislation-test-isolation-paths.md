---
lat:
  mode: explanation
---

# Why each isolated rspec run gets its own legislation tree

`Sway::LegislationTestIsolation` (`lib/sway/legislation_test_isolation.rb`) gives an isolated rspec run its own copy of the legislation tree, so two concurrent invocations don't collide writing to the same bind-mounted repo path.

`Sway::LegislationTestIsolation` (`lib/sway/legislation_test_isolation.rb`) gives an isolated rspec run its own copy of the legislation tree, so two concurrent invocations don't collide writing to the same bind-mounted repo path — each deleting the other's pipeline fixtures mid-run.

## Where the two variables come from

`Sway::LegislationTestIsolation` mirrors `config/database.yml`'s own `test.database` interpolation: the same two variables, the same per-run/per-worker shape.

`verify.sh` hands `SWAY_TEST_DATABASE_DIR` to each rspec lane, and `parallel_tests` sets `TEST_ENV_NUMBER` for workers 2 and up.

See `docs/explanation/env-read-check-design.md` for why this class reads `SWAY_TEST_DATABASE_DIR` and `TEST_ENV_NUMBER` directly from `ENV` instead of through `Sway::Settings`, and why that read is exempt from the app-wide `EnvReadCheck` guard.

## Why LegislationTestArtifacts mirrors the same shape for throwaway fixture files

`LegislationTestArtifacts` gives specs that exercise the legislation pipeline (`FetchBillsService`.

`LegislationTestArtifacts` gives specs that exercise the legislation pipeline (`FetchBillsService`, `FetchHearingsService`, `FetchLawService`, `GenerateDiffsService`, `Legislation::BillMetadata`) a place to put their throwaway fixture files, using the same `SWAY_TEST_DATABASE_DIR` / `TEST_ENV_NUMBER` variables `config/database.yml`'s `test.database` interpolation and `Legislation::Paths.root` already use — per-run and per-worker, respectively.

Every one of these specs used to hardcode `Rails.root.join("tmp", "test_artifacts", <name>)` directly — a FIXED path, not a per-run one — so two concurrent isolated runs still collided there even after `Legislation::Paths.root` itself was fixed for the same class of problem: one run's `rm_rf`/`mkdir_p` in a before/after hook raced the other's, producing `EINVAL` on `mkdir`, missing files, and wrong file content, all mid-run.

`LegislationTestArtifacts.root_for(name)` falls back byte-identical to `Rails.root/tmp/test_artifacts/<name>` — every one of these specs' path before this module existed — when neither variable is set, so an unisolated run (a plain `bundle exec rspec` outside `verify`) behaves exactly as it always did.
