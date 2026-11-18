---
lat:
  mode: explanation
---
# Deploy preflight

[[scripts/deploy.sh]] spends minutes installing gems, building the PDF extractor and uploading it before it first touches the image store. A preflight step does the outside checks first, in seconds.

## Why the checks run before the build

A deploy that fails at the image upload has already spent its slow minutes, and the failure says nothing those minutes needed.

Every check here asks a question a later step would ask anyway: can this
machine's Docker reach the image store, can the serving machine's Docker reach
it, and is the serving machine ready. Asking them first turns a failure at
minute four into one at second ten, with nothing built and nothing changed.

## What the preflight checks

Each check is bounded by a timeout, and the slow ones run at the same time, so the whole step takes as long as its slowest check.

- **Image store reach.** This machine's Docker daemon is asked for a tag that
  does not exist. "Not found" proves the daemon resolved the name, connected and
  spoke to the store, which is the path the build's upload takes; a check from
  this machine alone is not enough, because the daemon resolves and connects
  from its own virtual machine. The serving machine runs the same probe over
  the readiness connection, since it pulls from the store during the deploy.
  The probe needs no credentials. `kamal registry login` was the first choice
  and was dropped: it resolves every deploy secret before logging in, which took longer than
  a minute on 2026-11-18 and is paid again by the deploy itself.
- **Name lookup time.** The image store's name is looked up with a four-second
  limit. A slow answer is reported as a note, because Docker gives up on a slow
  lookup and then blames the connection — [[troubleshoot-deploys#Registry login times out]].
- **Serving machine readiness.** [[scripts/verify-pi.sh]] is streamed over one
  SSH connection and run as the deploy account. The disk to check is the mount
  holding `SWAY_STORAGE_DIR`, found on the machine itself; a storage folder on
  the root file system fails, because that is the SD card. A failed SSH
  connection is reported apart from a machine that is not ready.
- **Release state.** Uncommitted changes and a commit missing from its upstream
  branch are notes, not failures, because the release is named after the
  commit and a deploy of either ships something that name does not describe.

## Why some checks are skipped

A practice run and a first deploy skip the readiness check, because the check describes a production machine that has already been set up.

A practice machine's values are not in `deploy/config/sway.env`, and a first
deploy installs the PDF extractor that the check expects to find, so it would
fail on exactly the machine it is meant to let through. The probe from this
machine still runs for both.

`--skip-preflight` exists for a check that is wrong about a deploy that would
work. `--preflight-only` runs the checks and stops, so a fix can be confirmed
without starting a deploy.
