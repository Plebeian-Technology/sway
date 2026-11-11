---
lat:
  mode: how-to
---

# Move Sway to a new host

Move a running Sway installation, its SQLite database included, from the host that serves it now (the old host) to a different machine (the new host). The site is down for the length of the window.

**The addresses and account names are not in this file.** Commands below use the variable names from `deploy/config/sway.env` — copy `deploy/config/sway.env.example`, fill it in, then `set -a; . deploy/config/sway.env; set +a` before pasting any of them.

Two values carry the move:

- `SWAY_HOST` — set it to the **new** host. Every plain `kamal` command then acts on the new host.
- `SWAY_STANDBY_HOST` — set it to the **old** host. Commands that act on the old host carry the prefix `env SWAY_HOST=$SWAY_STANDBY_HOST`. After the move, the old host can stay on as the standby described in [[litestream-restore#Litestream — replication and restore runbook#The standby copy]], or be retired.

The commands assume `SWAY_STORAGE_DIR` is the same path on both hosts. If it is not, override it in each command the same way as `SWAY_HOST`.

`<your-domain>` below stands for one of the public names listed under `proxy.hosts` in `config/deploy.yml`. Everything before [[move-to-a-new-host#Move Sway to a new host#The window]] can be done on any day, with the site up.

## The one thing that must not happen out of order

Do not deploy to the new host until the old host's database is sitting on it.

The first thing a container does when it starts is copy the database it finds into the shared backup history in cloud storage. If the new host holds any other database — a seed database from a rehearsal deploy, or an empty one Rails created on first boot — a deploy uploads it as if it were production, and starts ageing the real copies out behind it. [[boot-backup-guard-design]] records the guard against this and why it exists.

Once `SWAY_HOST` names the new host, a plain `./scripts/deploy.sh` goes there. Do not run one until step W8 has passed.

## Before the window

These steps do not interrupt the site.

1. **P1 — Check the image store accepts the placeholder sign-in.** Bare `kamal` commands sign in to the image store with a placeholder, and the window is built on bare commands. Expect `Login Succeeded`; if it fails, stop and fix the registry login first.

   ```bash
   docker login $SWAY_REGISTRY -u anonymous -p unused
   ```

2. **P2 — Count the database migrations the deploy will run.** The deploy on the new host runs every migration production has not run yet, against real data, with the site down. Keep the output rather than piping straight into a count — a failed command writes to the error stream and leaves a count of zero that looks like a clean database.

   ```bash
   env SWAY_HOST=$SWAY_STANDBY_HOST SWAY_STORAGE_DIR=$SWAY_STORAGE_DIR \
     kamal app exec --reuse 'bin/rails db:migrate:status' > /tmp/migrate-status.txt 2>&1

   grep -c '^\s*down' /tmp/migrate-status.txt   # not yet run
   grep -c '^\s*up'   /tmp/migrate-status.txt   # already run
   ```

   The already-run count must be in the hundreds. If both are 0, the command never reached the database — read `/tmp/migrate-status.txt`. On the not-yet-run count:

   - **0 to a few** — carry on.
   - **More than a few** — pull a fresh copy of production's database and run the replay harness against it first (`RUN_PROD_DB_TESTS=1 dip run bundle exec rspec spec/production_readiness`). See [[production-snapshot-deploy-rehearsal-harness]].

3. **P3 — Check both hosts can read a database file, and record what the old host holds.** W5 and W8 run while the app is stopped, so they need the `sqlite3` command on each host itself. On the old host and again on the new host:

   ```bash
   command -v sqlite3 || echo "MISSING — use the fallback below"
   ```

   If it is missing, every `sqlite3 <path> "<sql>"` below becomes:

   ```bash
   docker run --rm -v $SWAY_STORAGE_DIR:/data \
     keinos/sqlite3 sqlite3 /data/production.sqlite3 "<sql>"
   ```

   Then, on the old host, record the baseline. These numbers drift before the window; they are a sanity check, not the comparison. The comparison that must match exactly is W5 against W8.

   ```bash
   sqlite3 $SWAY_STORAGE_DIR/production.sqlite3 \
     "SELECT COUNT(*) FROM users; SELECT COUNT(*) FROM user_votes; \
      SELECT COUNT(*) FROM bills; SELECT MAX(created_at) FROM user_votes;"
   ```

4. **P4 — Put the backup credential on the new host.** The replication accessory reads a key file that must exist before it starts. The script prints back the file's size and permissions from the target, so a partial write cannot pass as success.

   ```bash
   ./scripts/provision-litestream-key.sh --print-target   # expect <deploy user>@$SWAY_HOST
   ./scripts/provision-litestream-key.sh
   ```

5. **P5 — Clear any rehearsal off the new host.** Skip this if nothing has ever been deployed there. Otherwise stop the rehearsal's containers, then on the new host move its database aside — move rather than delete, until the move has stuck:

   ```bash
   cd $SWAY_STORAGE_DIR
   sudo mv production.sqlite3     rehearsal-seed.sqlite3
   sudo mv production.sqlite3-wal rehearsal-seed.sqlite3-wal 2>/dev/null
   sudo mv production.sqlite3-shm rehearsal-seed.sqlite3-shm 2>/dev/null
   ls -la
   ```

   Leave `production_queue.sqlite3` alone. It holds background jobs and is rebuilt on every boot.

6. **P6 — Build and upload the image.** The build is the slow part, so keep it out of the window.

   1. Check what the build will include. Anything uncommitted goes into the image:

      ```bash
      git status --porcelain
      git diff --stat Gemfile.lock package.json pnpm-lock.yaml
      ```

   2. Set aside any dependency changes, so the window moves the host and does not also change the code. Ship them afterwards as their own deploy:

      ```bash
      git stash push -m "deps — after the move" Gemfile.lock package.json pnpm-lock.yaml rbs_collection.lock.yaml
      ```

   3. Pin the image label. With anything uncommitted in the tree, including untracked files, Kamal names the image `<commit>_uncommitted_<random>` and picks a new random string on every run, so a later deploy looks for an image that was never pushed:

      ```bash
      export VERSION="$(git rev-parse HEAD)"
      ```

   4. Unlock your secret store so Kamal's secrets file can read it (the reference setup uses Bitwarden, as below), and export the release numbers by hand — this runbook does not go through `scripts/deploy.sh`, and without them the app reports itself as release 0:

      ```bash
      export $(cat .env.kamal | xargs)
      export BW_SESSION="$(bw unlock --raw)" && bw sync

      PREV_TAG="$(git tag --list 'release-*' --sort=-v:refname | head -n 1)"
      export SWAY_RELEASE_VERSION=$(( ${PREV_TAG#release-} + 1 ))
      export SWAY_RELEASE_SHA="$(git rev-parse HEAD)"
      export SWAY_PREVIOUS_SHA="$(git rev-list -n 1 "$PREV_TAG")"
      export SWAY_DEPLOYED_AT="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
      ```

   5. Build and push:

      ```bash
      kamal build push
      ```

   Do not commit anything after this point; the deploy looks for this exact label. Keep the terminal open — the window reuses these variables.

## The window

Roughly 10–20 minutes, most of it the deploy. The site is down from W1 to W11.

Three commands carry `SWAY_HOST=$SWAY_STANDBY_HOST` because they act on the old host; forgetting the prefix aims them at the new host, where those containers do not exist, so it fails loudly.

1. **W1 — Take the site down.** Traffic reaches Sway through a tunnel that dials out from the serving host, so stopping it takes the site off the internet:

   ```bash
   env SWAY_HOST=$SWAY_STANDBY_HOST SWAY_STORAGE_DIR=$SWAY_STORAGE_DIR \
     kamal accessory stop cloudflare_tunnel
   curl -sI https://<your-domain>/ | head -1
   ```

2. **W2 — Stop the app on the old host.** Nothing may write to the database from here on.

   ```bash
   env SWAY_HOST=$SWAY_STANDBY_HOST SWAY_STORAGE_DIR=$SWAY_STORAGE_DIR \
     kamal app stop
   ```

3. **W3 — Stop replication on the old host.** Two replicators writing to the same cloud path corrupt each other's history, and the new host's starts in W11.

   ```bash
   env SWAY_HOST=$SWAY_STANDBY_HOST SWAY_STORAGE_DIR=$SWAY_STORAGE_DIR \
     kamal accessory stop litestream
   ```

4. **W4 — Take one complete snapshot as the restore point.** On the old host:

   ```bash
   docker run --rm \
     -v $SWAY_STORAGE_DIR:/data \
     -v $SWAY_KEYFILE_PATH:/etc/litestream/gcs-key.json:ro \
     -e GOOGLE_APPLICATION_CREDENTIALS=/etc/litestream/gcs-key.json \
     litestream/litestream:0.5.15 \
     replicate -once -force-snapshot /data/production.sqlite3 \
     gs://$SWAY_GCS_BUCKET_DB/$SWAY_LITESTREAM_PATH
   ```

   If it rejects the database and destination given directly, point it at the config file the stopped accessory used; this prints where it is:

   ```bash
   docker inspect litestream --format '{{range .Mounts}}{{.Source}} -> {{.Destination}}{{"\n"}}{{end}}'
   ```

5. **W5 — Settle the database and record its numbers.** The checkpoint folds the write-ahead log back into the main file, so one file is the whole database. On the old host:

   ```bash
   sqlite3 $SWAY_STORAGE_DIR/production.sqlite3 "PRAGMA wal_checkpoint(TRUNCATE);"

   sqlite3 $SWAY_STORAGE_DIR/production.sqlite3 \
     "PRAGMA integrity_check; SELECT COUNT(*) FROM users; SELECT COUNT(*) FROM user_votes; \
      SELECT COUNT(*) FROM bills; SELECT MAX(created_at) FROM user_votes;"

   ls -la $SWAY_STORAGE_DIR/production.sqlite3*
   ```

   Write the numbers down. `integrity_check` must say `ok`.

6. **W6 — Copy the database to the new host.** From your workstation, or any machine that can reach both hosts. Copy only the main file; after the checkpoint the `-wal` and `-shm` files are empty or stale.

   ```bash
   scp <you>@$SWAY_STANDBY_HOST:$SWAY_STORAGE_DIR/production.sqlite3 /tmp/sway-move.sqlite3
   scp /tmp/sway-move.sqlite3 <you>@$SWAY_HOST:/tmp/
   rm /tmp/sway-move.sqlite3
   ```

7. **W7 — Put it in place with the container's owner.** The app inside the container runs as user 100, group 101, and cannot write to a database owned by anyone else. Skipping this fails minutes later as "the container never became healthy". On the new host:

   ```bash
   sudo mv /tmp/sway-move.sqlite3 $SWAY_STORAGE_DIR/production.sqlite3
   sudo chown -R 100:101 $SWAY_STORAGE_DIR
   sudo chmod 644 $SWAY_STORAGE_DIR/production.sqlite3
   ls -lan $SWAY_STORAGE_DIR
   ```

   `ls -l` without `-n` may print local names for those IDs (on Debian-based systems, including Raspberry Pi OS, `messagebus` and `crontab`). The numbers are what matter; do not "fix" the names.

8. **W8 — Check the copy against the original.** On the new host, as the container's user and group:

   ```bash
   sudo -u '#100' -g '#101' sqlite3 $SWAY_STORAGE_DIR/production.sqlite3 \
     "PRAGMA integrity_check; SELECT COUNT(*) FROM users; SELECT COUNT(*) FROM user_votes; \
      SELECT COUNT(*) FROM bills; SELECT MAX(created_at) FROM user_votes;"
   ```

   If the host has no account with ID 100, `sudo` refuses; run the P3 Docker fallback with `--user 100:101` instead.

   Run it as 100:101, not as your login and not as plain `sudo`. SQLite creates side files next to the database even to answer a query: as your login it fails with `attempt to write a readonly database`, and as root it leaves root-owned side files the app cannot write. Every number must match W5 exactly, and `integrity_check` must say `ok`. If anything differs, stop and roll back.

9. **W9 — Deploy to the new host.** The image is already uploaded, so this pulls and starts it, and applies the migrations P2 counted:

   ```bash
   echo "$VERSION"          # must match what P6 built
   kamal deploy -P --verbose
   ```

   If `VERSION` is empty, set it again with `export VERSION="$(git rev-parse HEAD)"` before deploying.

10. **W10 — Check it works before letting anyone in.** The proxy answers only for the configured public names, so send one in the `Host` header. Expect `200`, then confirm the app reads the copied data — both counts must match W5. If they do not, the app built a new database instead of using the copy; go no further.

    ```bash
    curl -sI -H 'Host: <your-domain>' http://$SWAY_HOST/up
    kamal app exec --reuse 'bin/rails runner "puts User.count; puts UserVote.count"'
    ```

11. **W11 — Start replication, then move the tunnel.** Replication first, so nothing is written without a copy being made. `boot` rather than `reboot`, because neither has run on this host before. Booting the tunnel is the moment traffic moves.

    ```bash
    kamal accessory boot litestream
    kamal accessory logs litestream | tail -20
    kamal accessory boot cloudflare_tunnel
    ```

12. **W12 — Check from outside.** Then, in a browser, sign in with a passkey and cast a real vote — that exercises the database, the passkey and writing. Watch the error reports for 30 minutes.

    ```bash
    curl -sI https://<your-domain>/ | head -1
    curl -sI https://<your-domain>/up | head -1
    ```

## Rolling back

The old host still has its database, images and containers, so rolling back needs no edit and no rebuild.

Rolling back is free until someone writes to the new host; after that, a rollback loses those writes unless the database is carried back the same way, so decide by W12.

1. Read the old host's version. `kamal app stop` printed it, or list the containers; the part after `sway-web-` is the version. Do not use plain `kamal app boot` — with no version it derives one from the current commit, which would run the new code on the old host.

   ```bash
   env SWAY_HOST=$SWAY_STANDBY_HOST SWAY_STORAGE_DIR=$SWAY_STORAGE_DIR \
     kamal app containers
   ```

2. Roll back to that version and bring the tunnel back up on the old host:

   ```bash
   env SWAY_HOST=$SWAY_STANDBY_HOST SWAY_STORAGE_DIR=$SWAY_STORAGE_DIR \
     kamal rollback <that version>

   env SWAY_HOST=$SWAY_STANDBY_HOST SWAY_STORAGE_DIR=$SWAY_STORAGE_DIR \
     kamal accessory boot cloudflare_tunnel
   ```

3. Stop replication on the new host (`kamal accessory stop litestream`), and only then start it again on the old host:

   ```bash
   env SWAY_HOST=$SWAY_STANDBY_HOST SWAY_STORAGE_DIR=$SWAY_STORAGE_DIR \
     kamal accessory boot litestream
   ```

## Afterwards

Once the new host has run cleanly for a day:

1. Tag the release:

   ```bash
   git tag -a "release-$SWAY_RELEASE_VERSION" "$SWAY_RELEASE_SHA" \
     -m "Release $SWAY_RELEASE_VERSION — $SWAY_DEPLOYED_AT — $SWAY_RELEASE_SHA"
   git push origin "release-$SWAY_RELEASE_VERSION"
   ```

2. Ship the dependency changes set aside in P6 as their own deploy, with the full suite behind them: `git stash pop`, run the gates, commit, deploy.
3. Test a restore from the backup on the new host, to a scratch file, and compare the numbers — see [[litestream-restore#Litestream — replication and restore runbook#Verify the restore path by hand]].
4. Optionally copy the old host's `legislation` folder across. It is a cache of downloaded bill documents that the pipeline refills by itself; without it the next pipeline run re-fetches from upstream and the admin cache panel shows those bills as uncached. See [[restore-the-legislation-artifacts]].
5. Delete `rehearsal-seed.sqlite3*` from the new host, if P5 created it.
6. Retune the container resource limits in `config/deploy.yml` for the new host's CPU and memory.
7. Restrict permissions on, or delete, the database copy left in `$SWAY_STORAGE_DIR` on the old host — and the `/tmp` copies from W6 — unless the old host stays on as a standby with its own restricted storage.
