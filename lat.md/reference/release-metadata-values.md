---
lat:
  mode: reference
---

# Release metadata values

`Sway::Release` exposes four canonical values describing the running deploy:

| Value          | Meaning                                                      |
| -------------- | ------------------------------------------------------------- |
| `version`      | Integer, equal to the `release-N` tag number (auto-increment) |
| `sha`          | Full commit SHA of `HEAD` at build time (this release)        |
| `previous_sha` | Commit SHA the prior `release-N` tag pointed at                |
| `deployed_at`  | UTC build/deploy timestamp                                    |

## Where the values come from

`scripts/deploy.sh` computes all four values *before* the image is built, threads them through `config/deploy.yml` `builder.args` into the `Dockerfile` as `ENV`, and they are baked into the production image.

- The running app reads them from `ENV` — it never needs `.git`, which is absent from the final image. After a successful `kamal redeploy`, `deploy.sh` creates and pushes the `release-<version>` git tag, so `version` is authoritative and monotonic across deploys.

## Per-environment behavior

Differences in commit SHA resolution and metadata provenance across production, test, and development.

- **Production** — `ENV` is always set by the build pipeline. `sha` never
  falls back to a live `git` read, because there is no `.git` in the image.
- **Development** — `ENV` is unset, so `sha` falls back to a guarded live
  `git rev-parse HEAD` read. The fallback never raises; it returns `nil` if
  `git` or the repository is unavailable.
- **Test** — `SWAY_RELEASE_SHA` is pinned in `config/environments/test.rb`,
  so specs never shell out to `git` and never depend on whatever commit
  happens to be checked out.
