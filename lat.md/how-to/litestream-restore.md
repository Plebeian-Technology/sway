---
lat:
  mode: how-to
---

# Litestream — replication and restore runbook

**The addresses and account names are not in this file.** They describe one installation, and this repository is public.

Commands below use the variable names from `deploy/config/sway.env` — copy `deploy/config/sway.env.example`, fill it in, then `set -a; . deploy/config/sway.env; set +a` before pasting any of them.

Continuous replication of Sway's primary production database to Google Cloud Storage, running as a Kamal accessory alongside the app.

Commands below are verified against **Litestream v0.5.15**. The 0.3.x CLI differs (`snapshots`/`wal` instead of `status`/`ltx`, a `replicas:` array in config) — do not follow 0.3-era examples found online.

## What is replicated

Sway continuously replicates `storage/production.sqlite3` to Google Cloud Storage using a dedicated writer service account and native GCS protocol.

| | |
|---|---|
| Source | `storage/production.sqlite3`, via the accessory's `/data` bind |
| Destination | `gs://$SWAY_GCS_BUCKET_DB/$SWAY_LITESTREAM_PATH` |
| Auth | Service-account keyfile at `$SWAY_KEYFILE_PATH` on the host, mounted read-only at `/etc/litestream/gcs-key.json` in the container and found via `GOOGLE_APPLICATION_CREDENTIALS`. Identity is your Litestream writer service account, `objectAdmin` on `gs://$SWAY_GCS_BUCKET_DB` only |
| Config | `config/litestream/litestream.yml.erb` → `/etc/litestream.yml` |
| Upload cadence | `sync-interval: 30s`, so a crash can lose up to about thirty seconds of writes |

The keyfile is pushed from your secret store (Bitwarden in the reference setup) straight to the host by `scripts/provision-litestream-key.sh`, which `scripts/deploy.sh` runs on every deploy. It is never uploaded by Kamal and never written into the working tree. To rotate the credential, replace the `LITESTREAM_GCS_SERVICE_ACCOUNT_JSON` item in the secret store and deploy — or run the script directly and `kamal accessory reboot litestream`.

Replication uses Litestream's **native `gs` client, not the `s3` type**. GCS is not reachable through the s3 type at all; the reasoning is recorded in `config/litestream/litestream.yml.erb`, and it is worth reading before anyone "simplifies" that config.

`production_queue.sqlite3` is **not** replicated — see the rationale at the foot of the config file.

This continuous copy is separate from the every-6-hours copies that `DatabaseBackupService` writes to `gs://$SWAY_GCS_BUCKET_DB/db/production/`. Both run, and each deletes its own old copies. They do different jobs: this one gets you back after a dead disk, the 6-hourly ones get you back after a bad migration or an accidental delete.

Old 6-hourly copies are deleted only after a new one has uploaded successfully. Otherwise failing uploads would let the delete-old-copies step keep running on schedule while no new copies arrived, and the retained history would shrink below the configured number of days.

## Health checks

The container is named after the accessory's `service:` value, so it is `litestream` on the host. It is distroless — there is no shell inside, so `docker exec` must invoke the binary directly rather than through `sh -c`.

### The three alarms, and which machine each one points at

`ReplicationLagCheckJob` runs every 15 minutes in production.

It is what actually watches replication now, not the commands this section used to recommend (see "What used to be here, and why it is gone", below). It sends one of three alarms to Sentry. Each alarm is forgiven once: it takes two consecutive 15-minute runs seeing the same fault before Sentry hears about it, so every alarm below carries the same bound — 30 minutes from the last good run to the alert. That is a different, tighter bound than the cron monitor's own 45-minute missed check-in bound, described further down.

**"Litestream has stopped copying the database. Go to the litestream accessory on the machine serving Sway. Recovery steps: docs/litestream-restore.md"** The copy's position did not move between two checks 15 minutes apart. Go to the litestream accessory on the machine serving Sway. Start with `kamal accessory logs litestream -f` and the authentication note below.

**"Sway cannot list the Litestream folder in the cloud bucket. Go to Sway's own Google credentials, not to the copier. Recovery steps: docs/litestream-restore.md"** Sway's own attempt to list the bucket failed twice in a row. This is not the copier's fault. Go to Sway's own Google credentials — the authentication note below covers the two likely causes.

**"Sway found no Litestream segment files under the path it was given. Go to SWAY_LITESTREAM_PATH in the deploy config. Recovery steps: docs/litestream-restore.md"** The bucket answered, but nothing was under the folder, twice in a row. Go to `SWAY_LITESTREAM_PATH` in the deploy config, not to the copier — the value is probably wrong, or the copier is writing somewhere else.

While any of these three keeps failing, Sentry keeps adding to the same issue every 15 minutes instead of opening a new one. A rising count and a "last seen" time that keeps moving both mean the fault is happening right now, not that it happened once and stopped.

The failure worth watching for is authentication, and it fails on every attempt rather than when the config is read — so the service starts up looking fine and then copies nothing. Two causes, in order of likelihood:

- the service-account key file is missing or unreadable at
  `/etc/litestream/gcs-key.json`. It is put on the host by
  `scripts/provision-litestream-key.sh`, which `scripts/deploy.sh` runs.
- that service account has no permission on `gs://$SWAY_GCS_BUCKET_DB`.

This paragraph is now the explanation behind the first two alarms above: an authentication fault stops the copier itself (the stall alarm) or stops Sway's own listing of the bucket (the read-failure alarm) — either way, it shows up here first.

### What fixed looks like

**"Litestream is copying the database again.

How long it was stopped is on this event. Nothing to do."** This message arrives once, at information level, on the run where the copy starts moving again. How long it was stopped is a field on the event, not part of the sentence above — the text has to stay fixed so repeats fold into one Sentry issue, so the duration could not go in it. The Sentry project clears the earlier issue on its own, once its own auto-resolve setting runs out. If that clears the issue before the fix has actually landed, it is harmless: a copier that is still broken reopens the issue within 15 minutes.

### Recovering from a Litestream replication stall (STALL_ALARM)

Recover from replication stall alerts without destroying local database state.

Do not run the destructive "Full restore after data loss" procedure when responding to STALL_ALARM on a healthy host: `storage/production.sqlite3` on the host is live, intact, and ahead of the stalled GCS replica.

1. Inspect the copier logs with `kamal accessory logs litestream -f` to see whether Litestream is failing authentication on `/etc/litestream/gcs-key.json`, encountering network or permission errors on `gs://$SWAY_GCS_BUCKET_DB`, or stopped.
2. Re-push the GCS service-account keyfile from your secret store if needed via `scripts/provision-litestream-key.sh` and restart the accessory with `kamal accessory reboot litestream`.
3. Verify a higher LTX segment number appears under `gs://$SWAY_GCS_BUCKET_DB/$SWAY_LITESTREAM_PATH/ltx/` via `gcloud storage ls -r gs://$SWAY_GCS_BUCKET_DB/$SWAY_LITESTREAM_PATH/ltx/` and confirm the next `ReplicationLagCheckJob` run emits the info-level recovery event.

### The cron monitor — the one piece of this that lives only in Sentry

Sway also registers a Sentry cron monitor, slug `replication-lag-check`.

Sentry creates the monitor itself the first time the job checks in — nothing in this repository can rebuild the monitor, its schedule, or any alert rules on it if they are ever changed or deleted, which is why the slug is written down here. A missed check-in is reported 30 minutes after the run was expected, which is 45 minutes after the last run that completed. That is a different, wider bound than the three fault alarms above, which alert 30 minutes after the last good run — this one covers the check itself failing to run at all, not a fault the check would otherwise catch.

A red monitor does not mean the copy stopped. It means the check itself failed to run at all, which usually means Rails or the job container is down — none of the three alarms above can fire if nothing runs to send them. The monitor's own auto-resolve setting in Sentry has to be turned on for a stale red monitor to clear itself once checks resume.

### Check by hand, if Sentry is unreachable

List the objects under the Litestream path in the bucket and read the highest number out of the file names. Nothing is downloaded — the answer is in the names.

```bash
gcloud storage ls -r gs://$SWAY_GCS_BUCKET_DB/$SWAY_LITESTREAM_PATH/ltx/
```

Names look like `<min>-<max>.ltx`, zero-padded, one folder per level under `ltx/`. Look at every level, not just `ltx/0/` — Litestream's own retention prunes level 0, so the highest number can sit at any level that is left.

This is the only method that was measured to be truthful. The copier's own status output is not — see the next section.

### What used to be here, and why it is gone

This section used to tell the reader to run `litestream status` and read the logs.

Both are gone now, because they can read healthy while uploads fail. `litestream status` reports the local position and the write-ahead-log size, not the copy's position — its own help text points at the logs, not at itself. The daemon can report that it is replicating, with a last-sync time that keeps advancing, while every upload is failing — that field moves on an upload attempt, not on a successful one. A command that can pass cleanly through a real outage does not belong on a page about recovering from outages, so it does not appear here, not even as an example of what not to run.

There is no region setting and nothing to get wrong about one. An earlier version of this file described a region mismatch in an SigV4 credential scope, which belongs to the S3 path this deliberately does not use — see the long note in `config/litestream/litestream.yml.erb`.

## The standby copy

**A backup nobody has restored is a hypothesis.** An optional standby host keeps its own copy of production on its own disk, fetched from the cloud copy on a daily timer.

Every run is also a live test of the recovery path, and it writes down how long the fetch took — which is the real recovery time.

The script is `scripts/standby-restore.sh`. It runs **on the standby host**, not on your workstation, and not under Kamal — the standby is not a deploy target and this must not depend on the deploy tooling. A systemd timer and the `litestream` container image are the whole thing.

The standby pulls rather than the primary host pushing, because Litestream 0.5 takes exactly one destination per database and that slot holds the cloud copy. It is also the safer shape: a second replicator beside the live database is a second writer.

**First-time setup.** From your workstation:

```bash
scripts/provision-litestream-key.sh $SWAY_STANDBY_HOST     # send the GCS keyfile to the standby host
```

Then copy `scripts/standby-restore.sh` to the standby machine and run it there.

**The script holds no values of its own** — it comes from a public repository, so it names no folder, no cloud bucket and no sign-in file. You pass them in once, and `install` writes them to `/etc/default/sway-standby-restore`, which is where the timer reads them from afterwards.

```bash
sudo apt-get install -y sqlite3     # the image is distroless; the checks need it on the host

# Everything the script needs, in one place. Take the values from
# deploy/config/sway.env on the machine you deploy from.
export SWAY_STANDBY_DIR=...        # where the copy is kept
export SWAY_STANDBY_MOUNT=...      # the data disk that folder sits on
export SWAY_REPLICA_URL=gs://...   # $SWAY_GCS_BUCKET_DB/$SWAY_LITESTREAM_PATH
export SWAY_GCS_KEY=...            # where provision-litestream-key.sh put the sign-in file

./standby-restore.sh check         # says what it would do, writes nothing
sudo -E ./standby-restore.sh install   # -E keeps the variables through sudo
sudo -u kamal /usr/local/sbin/sway-standby-restore run
/usr/local/sbin/sway-standby-restore status
```

Leave one out and the run stops and names it. `sudo` without `-E` throws the variables away, so the install would stop and name all four.

The first successful `run` is what proves the path, and every later run repeats it.

**How it stays harmless when it fails.** The fetch goes to a scratch name, the copy is checked (`integrity_check`, plus row counts for `users`, `user_votes` and `bills`), and only then is it moved into place on the same disk. A fetch that dies halfway leaves the previous good copy exactly where it was. The unit carries `RequiresMountsFor`, so a run cannot start while the data disk is absent — without that, the copy lands on the boot disk, fills it, and reports success.

**It holds no values of its own.** It used to carry copies of three settings that also live in the deploy config, and a test pinned the two against each other so they could not drift. Now there is nothing to drift: the values live on the machine, in `/etc/default/sway-standby-restore`, and `spec/config/standby_restore_spec.rb` fails if any address, cloud folder or disk path reappears in the script.

The "no disk path" check allows a path to appear in the script only when it is the SAME on every machine that could run it. Three kinds qualify: where the script installs itself and where systemd keeps its units; the shebang and `/dev/null`, fixed by the operating system; and paths INSIDE the container, which the image decides rather than the host. Anything else describes one machine's disk and has to come from the settings file instead.

**What it does not cover.** The standby's copy comes *from* the cloud copy, so it does not protect against the cloud copy being wrong. It protects against the primary host's disk dying, and against the cloud being slow or unreachable when it is needed. The 6-hourly snapshots from `DatabaseBackupService` are the separate lineage.

## Verify the restore path by hand

The standby timer above does this daily. To check it once, on demand:

```bash
docker exec litestream litestream restore -dry-run /data/production.sqlite3

docker exec litestream litestream restore \
  -o /data/verify-restore.sqlite3 \
  /data/production.sqlite3

docker exec litestream litestream restore -o /dev/null -dry-run /data/production.sqlite3
```

Then compare against the live database and delete the copy:

```bash
sqlite3 $SWAY_STORAGE_DIR/verify-restore.sqlite3 \
  "PRAGMA integrity_check; SELECT COUNT(*) FROM user_votes; SELECT COUNT(*) FROM users;"

rm $SWAY_STORAGE_DIR/verify-restore.sqlite3
```

Row counts should match the live database, or exceed the last snapshot in `db/production/`.

## Full restore after data loss

Recover from catastrophic data or host loss by restoring the full database from the remote GCS replica into the local storage path.

1. **Stop the app first.** Nothing may write to the database path during a
   restore.

```bash kamal app stop        # from your workstation ```

2. **Stop the replicator**, so it does not replicate the damaged state or
   contend for the file.

```bash kamal accessory stop litestream ```

3. **Move the damaged database aside** rather than deleting it. It may still
   hold data the replica does not.

```bash cd $SWAY_STORAGE_DIR mv production.sqlite3 production.sqlite3.damaged mv production.sqlite3-wal production.sqlite3-wal.damaged 2>/dev/null mv production.sqlite3-shm production.sqlite3-shm.damaged 2>/dev/null ```

4. **Restore.** Mount the host keyfile and point
   `GOOGLE_APPLICATION_CREDENTIALS` at it. A `gs://` replica URL is
   self-describing, so no config file is needed — restoring by URL works
   anywhere the keyfile is available, including from a laptop.

```bash docker run --rm \ -v $SWAY_STORAGE_DIR:/data \ -v $SWAY_KEYFILE_PATH:/etc/litestream/gcs-key.json:ro \ -e GOOGLE_APPLICATION_CREDENTIALS=/etc/litestream/gcs-key.json \ litestream/litestream:0.5.15 \ restore -o /data/production.sqlite3 gs://$SWAY_GCS_BUCKET_DB/$SWAY_LITESTREAM_PATH ```

5. **Verify before booting.**

```bash sqlite3 $SWAY_STORAGE_DIR/production.sqlite3 \ "PRAGMA integrity_check; SELECT COUNT(*) FROM users; SELECT MAX(created_at) FROM user_votes;" ```

6. **Boot**, replicator first so nothing is written unreplicated.

```bash kamal accessory boot litestream kamal app boot ```

## Point-in-time restore

To recover from logical damage — a bad migration, an accidental delete — rather than media failure, restore to just before it:

```bash
docker exec litestream litestream restore -config /etc/litestream.yml \
  -timestamp 2026-07-28T18:00:00Z \
  -o /data/production-pit.sqlite3 \
  /data/production.sqlite3
```

`-txid` restores to a specific hex transaction ID instead. Always restore point-in-time to a *new* path and inspect it before swapping anything in.

## Seeding a new host

Moving Sway to a new host copies the settled database across directly rather than restoring from the replica, then verifies it before any deploy.

The full procedure, including taking a forced snapshot as the restore point first, is [[move-to-a-new-host]].

## Cautions

Operating Litestream safely requires observing concurrency limits, avoiding manual WAL truncations, and isolating replica bucket credentials.

- **Never run `PRAGMA wal_checkpoint(TRUNCATE)` behind a running replicator.**
  Stop the accessory before quiescing the database by hand.
- **Only one replicator may write to a replica path.** Two writers corrupt the
  generation history. A practice or rehearsal host needs its own config file
  writing to its own path, and a host move stops the old replicator before the
  new one starts.
- **Client-side encryption is unavailable.** Age encryption was removed in
  0.5.1+ during the LTX refactor. The replica is protected by GCS
  server-side encryption and IAM scope, nothing more — so the SERVICE ACCOUNT
  whose key file sits at `/etc/litestream/gcs-key.json` must stay scoped to
  `gs://$SWAY_GCS_BUCKET_DB` and never be reused. (An earlier version of this said "HMAC
  key". Nothing here authenticates with one: the native `gs` client reads
  Google's standard credential chain, and the HMAC/S3 route is the one that
  could not be made to work at all.)
- **Litestream replicates faithfully, including mistakes.** If the storage
  volume goes missing and the app seeds an empty database, that empty database
  is what gets replicated. The guard against that is
  `RequiresMountsFor` on the docker unit, which stops the unit from starting while
  the storage mount is missing.
