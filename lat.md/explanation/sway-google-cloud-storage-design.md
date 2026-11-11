---
lat:
  mode: explanation
---

# SwayGoogleCloudStorage design notes

Why SwayGoogleCloudStorage's keyfile writer used to rewrite the private key on every call, and what fixed it.

## Why dependencies are required explicitly (Rakefile load order)

`lib/tasks/sway_task.rb` loads `lib/sway_google_cloud_storage.rb` with a plain `require` while the Rakefile is loading tasks — before Rails' own autoloader (Zeitwerk) exists, so nothing in this file gets loaded automatically.

The `active_storage_credentials` initializer then calls `.credentials` in that same early window. Because neither autoloader is available yet, every dependency this file needs (`sway_logging`, `sway_deploy_config`) has to be required explicitly with `require_relative` rather than left for Zeitwerk to resolve.

## Why .write_keyfile skips redundant writes

`SwayGoogleCloudStorage.write_keyfile` (`lib/sway_google_cloud_storage.rb`) skips writing when the file already holds exactly the payload it was about to write.

Before this check existed, the raw private key was rewritten on every single call — at boot and on every use of storage — because the cached value was never reused.

`.write_keyfile` writes the service-account key file so only its owner can read it (mode `0600`; it used to be world-readable `0644`). The permissions are still re-applied if they have drifted, even when the skip-write path is taken.

`.credentials` also used to print three `puts` sanity checks to stdout on every call, including in production. It now prints nothing.

## Why SwayAudio reports a missing bucket to Sentry instead of a useEffect

`SwayAudio` has no `useEffect` for its bucket check: whether a bucket exists is decided when the bundle is built, so this can never change while the component is alive — there is nothing to re-run and nothing to clean up.

An effect would only add a second render pass.

A normal deploy cannot reach the missing-bucket case: `config/deploy.yml` stops and names the value when `SWAY_GCS_BUCKET_ASSETS` is missing, before the image is built. It IS reachable by building the image without that file — and then nothing else would say so, because a missing player looks exactly like a bill that has no audio. `SwayAudio` tells Sentry rather than the reader: an operator can fix this and a reader cannot.

## Why the frontend bucket name is a build-time Vite variable, not a constant

`app/frontend/sway_constants/google_cloud_storage.ts` is where Sway's audio files are served from.

THE BUCKET NAME IS NOT WRITTEN HERE. It names one person's cloud account, and this repo is public, so it arrives at build time instead. The value comes from `SWAY_GCS_BUCKET_ASSETS` in `deploy/config/sway.env`, the same one place every other deploy value is read from.

Vite gives a variable to browser code only when its name starts with `VITE_`, and it fixes the value into the bundle when the assets are built. So changing the bucket needs a rebuild, not just a restart.

A build with no bucket set leaves this empty rather than guessing a name. Callers must check it before they use it. `SwayAudio` does.
