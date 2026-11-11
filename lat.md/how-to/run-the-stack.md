---
lat:
  mode: how-to
---
# Run the stack locally

The development environment runs entirely under `dip`. SQLite databases live in the `sway_storage` Docker volume, and `config/boot.rb` blocks Rails from booting on the host, where it would open a different, empty `storage/`.

## Steps

First-time provisioning through to a running stack with data loaded.

1. Run `dip provision` once. It builds the images, creates mkcert certificates, drops the development, test and preview databases, and creates them again from the schema and seeds. Everything in them is lost, bill summaries included; run `dip run rails db:migrate` instead to keep it.
2. Start `llama-server` on the host at port 8888 if bill seeding is needed. `db:seed:bills` calls it for summaries and fails with connection-refused otherwise; plain `db:seed` and `db:reset` do not need it.
3. Run `dip run dev` to start the full stack — rails, vite, caddy, jobs, cloudflared.
4. Browse to `https://localhost:3333`. Caddy fronts `web:3000` and `vite:3036`.
5. Run `dip run rails seed` to load data. It runs `db:seed`, `db:seed:bills`, and a score recompute.

## One-off commands

Every command below reaches the same named-volume database.

- `dip run rails c` — console
- `dip run rails db:migrate` — migrations
- `dip run bundle exec rake <task>` — focused rake tasks go through `bundle exec`

## Working in a phase worktree

A worktree gets tracked files only, so it has none of the `.env` files and compose refuses to start. `deploy/config/sway.env` is untracked too, and every rake task reads it at load.

1. Run `scripts/dip/secrets-root.sh` once, before any other `dip` command. It points compose at the main checkout's copies rather than copying keys into a tree agents read.
2. Skip step 1 for `dip provision`, `dip run rspec` and `dip run verify` — each calls the script itself.
3. Re-run any red gate on the main checkout before believing it. Rails credentials read as absent in a worktree, because `config/master.key` is untracked and is deliberately not reached for.

The script writes two path lines into `.dockerdev/.env` and no secret: `SWAY_SECRETS_ROOT`, which every `env_file:` entry resolves against, and `SWAY_DEPLOY_CONFIG_SRC`, the source of a read-only bind mount onto `/app/deploy/config/sway.env`. Without that mount a rake task in a worktree stops at `SwayDeployConfig::MissingValue`, because `SwayDeployConfig` reads the file from inside the container and a `.git`-style pointer or host symlink cannot cross a container mount. The file stays in the main checkout, which is what keeps the keys out of a tree agents commit from. Unset, the mount source resolves to the invoking checkout's own file, so the main checkout behaves as it did before.

## Git inside a worktree's container

A linked worktree's `.git` is a file holding an absolute host path into the main checkout's `.git`, which the `..:/app` bind mount does not reach, so every `git` call in a container exited 1.

1. Run `scripts/dip/secrets-root.sh`, as step 1 above already asks. It writes `SWAY_GIT_COMMON_SRC` and `SWAY_GIT_COMMON_AT`, both the main checkout's `.git`.
2. Read the mount it drives in `.dockerdev/compose.yml`: source and target are that same absolute path, so the pointer inside `/app/.git` resolves to the directory it names. Read-only, because nothing in a container should rewrite the main checkout's object store.
3. Expect `safe.directory` to be `*` in every backend service. Git compares a repository directory's owner with the effective user id of the process reading it and stops with a dubious-ownership error when they differ, which is what a container running as root over host-owned files produces.

Unset, the mount source is this checkout's own `.git` and the target is an unused path, so the main checkout is not affected: `git` there resolves `/app/.git` through the writable `..:/app` bind, as it always did.

## When a check shells out to git

A check that runs `git` rescues the case where the binary is absent and says so
in plain words.

Git has already been observed failing inside a container in a worktree, and an
unrescued file-not-found error there surfaces as a raw backtrace rather than as
the fact that matters: the check did not run at all. A check reporting nothing
looks the same as a check finding nothing.

## If port 3333 appears dead

A stale host Rails process can hold `:3333`, which makes Caddyfile edits appear to do nothing.

1. Check for a host Rails process holding the port.
2. Stop it, then restart `dip run dev`.

## If edits stop reaching the browser

The Vite container serves `/@vite/client`. When that one path returns 404 while every other endpoint works, pages still load and saved edits stop reaching the browser.

1. Watch the `dip run dev` output for `dev.sh: the Vite hot-reload client at /@vite/client is not answering`. A healthcheck on the `vite:` service in `.dockerdev/compose.yml` fetches that path every 30 seconds, and `scripts/dip/dev.sh` prints the line each time the container turns unhealthy.
2. Run `docker restart sway-vite-1`.
3. Save a frontend file and confirm the page updates without a manual reload.

The healthcheck reports only. No service declares `condition: service_healthy` against `vite`, so startup ordering is the same with it as without it. The watcher is a `docker events` stream started before `dip up` and killed by an `EXIT` trap.
