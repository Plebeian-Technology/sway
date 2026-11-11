---
lat:
  mode: explanation
---

# Sway Google Cloud Storage

The module every part of Sway uses to reach Cloud Storage. It loads earlier than the rest of the application, and it writes files that other processes are reading, so two of its constraints are invisible from its call sites.

## Browser uploads depend on the live bucket policy

An Active Storage metadata response does not prove the browser can upload bytes. The subsequent signed PUT reaches Cloud Storage directly, where the live bucket CORS policy decides whether the application origin is allowed.

Active Storage direct uploads send `Content-Type`, `Content-MD5`, `Content-Disposition` and `x-goog-content-length-range` on signed PUT requests, while resumable uploads send `x-goog-resumable`. A preflight that names a header the bucket does not allow gets a 200 with no `Access-Control-Allow-Origin`, so the browser drops the PUT and Active Storage reports `Status: 0`. Active Storage adds headers between releases, so the spec checks every header its cloud storage service asks for against the rule rather than a copied list.

`SwayGoogleCloudStorage.configure` applies the required CORS policy directly to the live bucket. It clears any prior rules and restricts allowed origins to `BUCKET_CORS_ORIGINS` (including `https://app.sway.vote` and local development origins), allows `PUT` and `GET` methods, allows the five upload headers, and sets a 3600-second preflight cache. Preflight validation confirms that approved application origins receive the appropriate access control headers while unapproved origins remain refused, preserving origin isolation without altering the server-side `AdminOnlyDirectUploads` guard.

## Why dependencies are required explicitly

`lib/tasks/sway_task.rb` loads this file with a plain `require` while the Rakefile is loading tasks, before Zeitwerk exists, so nothing in it resolves automatically.

The `active_storage_credentials` initializer then calls `.credentials` in that
same early window. With neither autoloader available, every dependency the file
needs is required explicitly with `require_relative` rather than left for
Zeitwerk to find.

The rule governs anything added later, and it binds harder than it looks: a
constant from `app/` cannot be named in this file at all, however close a fit it
is. That is why the atomic write below is spelled out here rather than reusing
`Legislation::AtomicWrite`, which does the same thing one directory away.

## A mirrored photo keeps its source address

The mirror stores a local attachment while the record keeps the original
outside URL.

[[app/services/external_asset_mirror_service.rb#ExternalAssetMirrorService]]
attaches the downloaded image without replacing the source URL. When a reader
uses [[app/services/mirrored_asset_url.rb#MirroredAssetUrl]], an attached
copy produces a Sway storage URL and a missing copy falls back to that source
address. The fallback may be stale or unavailable; retaining the URL does not
claim that its host will keep serving the image.

The mirror does not rewrite `photo_url`; the bounded retirement policy for
unavailable historical addresses is described in
[[sway-google-cloud-storage#Historical photo URLs are retired by exact identity]].

The legacy [[lib/tasks/reset_legislator_photo_urls.rake]] task can write
photo URLs from committed JSON into database rows. Its relationship to the
canonical roster file is described in
[[current-legislator-term#Missing source fields preserve stored roster values]].

## Historical photo URLs are retired by exact identity

Unavailable historical addresses are cleared only by a bounded identity-and-URL match; stored photo attachments remain available.

The retirement policy preserves existing attachment rows and files. It clears
only the four selected stale `photo_url` values when locale identity, external
ID, and the exact old address all match; it does not guess an archive address
or clear a replacement value written after the snapshot. The other three
scoped identities have blank photo URLs. This policy is separate from routine
roster refresh, whose baseline and source-silence behavior are described in
[[current-legislator-term#Missing source fields preserve stored roster values]].

[[db/data/20261007000001_retire_unavailable_legislator_photo_urls.rb]] applies
the bounded cleanup. The standing
[[spec/production_readiness/production_legislator_photos_spec.rb]] gate checks
that every missing photo attachment belongs to a legislator the seed guard can
update. [[db/seeds/seedable.rb#Seedable#seed_or_skip?]] skips ordinary updates
to records changed since their last seed, so a refused row can otherwise remain
without a photo after deployment.

The snapshot example also requires a substantial roster and at least one
unattached photo, so an absent or empty snapshot cannot make the seed-guard
check pass vacuously. It does not pin the snapshot's exact roster or missing
photo counts.

## Only consumers of mirrored assets declare the callback

The callback belongs to a model whose readers use its downloaded attachment.

[[app/models/concerns/mirrors_external_asset.rb#MirrorsExternalAsset]] queues
the copy after its source URL changes. The callback skips blank, hostless,
Sway-host, and already-in-bucket values, as described in
[[sway-google-cloud-storage#A stored file name is not an address]]. Other
host-bearing values can enqueue a job; the mirror service rejects unsupported
schemes before downloading them through
[[app/services/external_asset_mirror_service.rb#ExternalAssetMirrorService]].
Organization icons and legislator photos use their attachment-backed copies.
[[app/models/sway_locale.rb#SwayLocale#to_builder]] continues to expose
`icon_url` as jurisdiction metadata, but no reader resolves a mirrored locale
icon, so the locale does not declare this callback and the batch task does not
scan it.

## How a destructive task refuses to be run by accident

The task that reassigns every reader's legislators has no description, so it
stays out of the task listing and cannot be found by browsing, and it refuses
to start without an explicit confirmation variable.

It is destructive twice over: it marks every existing link inactive and then
calls external services to build new ones. Those two properties are why it
deactivates one reader at a time rather than all of them up front, and why each
locale's reassignment sits in its own rescue — an external service failing
partway then strands one reader in one locale, rather than leaving every reader
with no active legislators and wrong score and accountability pages. The
external call is deliberately not wrapped in a database transaction, since a
transaction held open across a network call is the other way to make the
failure worse.

## What the bucket says about caching audio

A bill's audio summary is fetched by the browser straight from the bucket, so the only caching instruction a reader ever sees is the one the object itself carries.

Nothing set one. The player builds `https://storage.googleapis.com/<assets bucket>/<path>` in the browser, which means the request never passes through Sway or Cloudflare and cannot be given a header on the way out. An audio file is also the largest thing Sway serves — orders of magnitude past a 10 KB icon — so what the bucket answers with decides whether it is fetched once or every time.

`SwayGoogleCloudStorage::AUDIO_CACHE_CONTROL` is that instruction: public, one week. It is deliberately not `immutable`, and deliberately not a year. An audio object is addressed by locale and name rather than by its content, and the admin upload writes to that same name again when a summary is re-recorded, so a copy held anywhere has to expire on its own or a corrected recording would go unheard.

Two paths write it. `upload_file` takes a `cache_control:` argument for anything Sway uploads itself, and `Sway::AudioCacheControl` — `bundle exec rake sway:assets:audio_cache_control` — walks the bucket and writes the instruction onto objects already there. The task reports by default and writes only when asked, and it skips an object that already carries the value, so running it twice costs one listing.

What the upload path cannot do: an admin upload reaches the bucket directly through a pre-signed PUT URL, so the header the browser does not send cannot be added by the server at the moment the object is written. `AudioCacheControlJob` therefore runs the same pass every week in production, scheduled in `config/recurring.yml`, which is what stops the bucket drifting back to uncached objects after each new recording. It is production-only because a developer machine holds no service-account key for the bucket.

## A stored file name is not an address

Some rows hold a bare bucket file name where an address is expected, and what is serialized has to be a full escaped storage address.

A bare name has no scheme, so a browser resolves it against whatever page it is
on and asks for something that does not exist — 34 organizations carried one, and
each produced a 404 rather than a missing image. The same distinction decides
which addresses are worth mirroring into Sway's own storage: one that is already
Sway's is not copied, and getting that test wrong queues a copy job whose only
possible outcome is a refusal.

## Why a download lands through a temporary file

Every download writes to a hidden sibling of its destination and renames it into place, because a deploy runs the same download in more than one container at once against a single shared directory.

`config/deploy.yml` bind-mounts one host directory into `/rails/storage`, and before `bin/docker-entrypoint` scoped `rake sway:deploy` to the web server branch (see [[production-snapshot-deploy-rehearsal-harness#Why the entrypoint runs sway:deploy and database setup only on web server startup]]), both the web and job containers executed `rake sway:deploy` on startup and downloaded the same seed and geojson objects to the same paths at approximately the same moment. Overlapping web containers during a rolling deploy or restart share that same mount.

The client writes each file in place and then verifies it by reading that path
back. A second container truncating the path inside that window makes the first
one's verification fail, which surfaces as a CRC32c mismatch and stops the
deploy. Nothing is wrong with the stored object; the file on disk was rewritten
underneath the check. It appears only sometimes, because whether it happens
depends on how the two container starts overlap.

Renaming is atomic, so a reader sees either the previous file or the complete
new one and never a partially written one. Two containers writing identical
bytes and then renaming is harmless: whichever lands last wins, and the content
is the same either way. Verification moves to the temporary file, which only the
container writing it can touch.

The independent gain is that an interrupted download no longer leaves a
truncated file behind for the next boot to read. `BootBackupGuard` solves the
neighbouring instance of this problem — the entrypoint's database backup — by
running once per deploy instead of once per container start, and that shape
would have prevented this race too. The file-level fix is preferred here because
it also covers the interrupted download, and because it needs no shared state to
decide whose turn it is.

## Why credentials tolerates a nil private key at boot

[[lib/sway_google_cloud_storage.rb#SwayGoogleCloudStorage]] (`credentials`) uses safe navigation (`&.gsub`) when normalizing newlines on the Google Cloud Storage private key.

A fork or local checkout without production Cloud Storage credentials still has to boot far enough to run provisioning and preview steps; a nil private key is harmless until a storage operation actually runs.
