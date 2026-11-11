---
lat:
  mode: explanation
---
# Building the production image

The image is built in stages on one architecture and run on another, over a slow link, so several of its lines exist because of what a layer costs to push or because a step failed silently for a long time.

## Where the compiled Ruby cache lives

Bootsnap's cache is given a path of its own at the image root rather than the default inside the application's temporary directory.

The default sits in a directory the build stage deletes and the final stage
never copies, so both precompile steps cost build time and shipped nothing, and
every container start rebuilt the whole cache before it could serve a request.
Putting it inside the gem directory instead is tempting and wrong: the
application has to be able to write this one directory, while the gems around it
stay owned by root.

Only the compile cache is precompiled. The load-path cache has no precompile
step — it is built at boot or not at all — which is why making the whole thing
read-only was rejected: that would suppress the load-path write permanently, in
order to protect a directory that is already writable.

Order matters in the build stage too. Pruning unused gems after the precompile
meant compiling gems that were about to be removed, and left the cache under a
directory another command had just been pruning; cleaning first and compiling
what survives is the same work done once. Mounting
`/usr/local/bundle/ruby/4.0.0/cache` as a BuildKit cache keeps downloaded `.gem`
archives out of the image layer while reusing them across builds, and pruning
`mini_portile2` compiler directories (`ports/`, `tmp/`), C/C++ extension sources
(`*.c`, `*.h`, `Makefile`, `src/`, `include/`), intermediate `.o`/`.a` object
files, type definitions (`rbi/`, `sig/`), test/doc trees (`spec/`, `test/`,
`doc/`, `docs/`, `examples/`, `benchmarks/`), and precompiled binaries for older
Ruby minors (`nokogiri/3.*`) before `bootsnap precompile --gemfile` leaves only
the linked `.so` shared libraries (in `extensions/`, `lib/`, and `ext/`) and
Ruby sources needed at runtime.

## Ownership is set by the copy, never by a later chown

Directories that the application has to write arrive already owned by it, because a recursive ownership change afterwards is recorded as a whole new layer.

Three of them used to arrive owned by root and were then fixed by one recursive
command. Measured, the built assets directory alone is 208 MB, and it shipped
twice inside a 1.3 GB image — pulled twice, over a slow link, on every
deploy.

## Why the SQLite options are written as local bundler configuration

Which options reach the database engine, and why two of them are forbidden, belongs to [[toolchain-pins#Why the dockerfile gates read every file and then read the running library]]. Where they are written is this file's part of it.

They used to live only in an ignored per-machine configuration file, so they
applied on one developer's machine and reached neither production nor the
continuous-integration runner. Writing them as *local* configuration inside the
image is what makes them win: local configuration outranks both the environment
and global configuration in the bundler's own precedence order, and nothing else
in this image writes that file.

The development image cannot do the same thing, and uses an environment variable
instead. Its local configuration path sits inside the directory compose
bind-mounts the checkout over at run time, so anything written there during the
build is masked the moment the container starts. That makes it a fallback rather
than the last word — a developer's own local configuration file still outranks
it, which keeps a deliberate override working and means a stale one can silently
put the container on different options. Reading the options back from a running
container is the only way to know which won.

## Why the package manager floats within its major

The package manager is installed as the newest release of its current major version, and there is no separate pin elsewhere for it to match.

Two pins that have to agree is the arrangement that drifts. Moving to the next
major is a deliberate edit here and in the workflows, which is the only place
the version is named.

`package.json` carries no `packageManager` field for the same reason. An exact
version there is enforced on every machine that reads the manifest, so a
developer's own machine could not run a newer release of the same major without
the tree being edited — the pin's whole cost, for a range within which the
releases are meant to be interchangeable.

## Why a build secret has to be exported

A bare assignment inside a build step creates a shell variable that no child process inherits, so a build tool reading it from the environment sees nothing.

That is exactly what happened to the source-map upload token: the build read the
secret and threw it away, for as long as the line had existed, while the two
lines beside it — which did export — made the omission easy to miss. Proved
rather than assumed on the image itself, a plain assignment reads back as
nothing from a child process and an exported one reads back the value.

The reporting address is missing on purpose for anything that is not a real
deploy, which is why reading it tolerates absence rather than failing: a preview
must not report anything, because what it sent would arrive looking exactly like
the live site.

## Why the source maps are deleted only when they were uploaded

The maps are removed from the image only when this build could have uploaded them, because deleting them otherwise destroys the only copy.

They are 140 MB of the 208 MB the assets directory holds — 1700 files against
33 MB of actual JavaScript — and a browser never asks for one. With all three
upload values present the build fails if the upload fails, so an image that
reaches the deletion has uploaded its maps.

The condition has to be the same three values the build configuration itself
tests. This is one decision written in two places — the configuration decides
whether to upload, this line decides whether to delete — and when the two
conditions differ, the gap between them is a build that deletes the maps after
uploading nothing. Testing only the token left exactly that gap, measured by
resolving the configuration with a token but no organization or project, which
produces a plugin list with no upload plugin in it. A spec holds the two lists
together.

The deletion is a shell condition rather than the upload plugin's own
after-upload option, so that one place decides it: the plugin's glob runs at
bundle-close, before both the upload finishing and the licence snapshot beside
it.

## Why the build context excludes built output by pattern

The directories the frontend build writes into are excluded from the build context by the pattern they share rather than one at a time.

Listed separately, each new one had to be noticed by a person, and one was not —
so a developer's own build output was shipped in the image and served to anyone,
carrying that machine's own map files and build-time values. The image builds its
own assets, so none of that is a build input in the first place.

Measured, the unnoticed directory carried 180 MB and 1,461 stale map files, and
the real build was then written alongside those rather than over them: the image
depended on a working tree instead of on the source, so two builds of the same
commit gave two different images. The pattern itself was tested rather than
assumed — a throwaway build proved it drops the three build directories while
keeping the one holding the compiled stylesheets. Both ignore files also exclude
knowledge-graph caches (`/lat.md/`), profiling traces (`/browser_profiling/`),
browser drivers (`/chromedriver/`), documentation (`/docs/`, `/screenshots/`),
frontend test suites, and host typechecker binaries (`/bin/steep-rs*`) so
non-runtime tooling never enters the build context or `/rails/bin`.

## What the final image keeps of the frontend

The frontend source is deleted from the image except for one table Ruby reads while loading.

Deleting the whole directory stopped the container starting, because that one
file is read during eager loading. A spec holds the deletion and the exception
together, so a file added to that directory does not quietly become a fourth
thing the image needs.

## Why the allocator is replaced, and how that can be undone silently

The image installs an alternative allocator and preloads it, because the C library it runs on fragments under threads and the web container runs several worker processes of several threads each.

The saving at boot is small and boot time is unchanged. That is the
single-threaded case, which is the one this change is least able to help; the
threaded case under load is the reason the package is there.

The preload line and the package have to stay together, and nothing enforces
it. A missing preload target is ignored by this C library — no error, no
warning, the process simply runs on the system allocator — so removing the
package would not break the build or the boot. It would quietly undo the change
and leave a line that reads as though it were still working, which is why the
check is made inside a running container rather than by reading either line.
Companion `MALLOC_CONF` settings
(`dirty_decay_ms:1000,muzzy_decay_ms:1000,narenas:2,background_thread:true`)
cap each Ruby process at two allocator arenas, return freed dirty and muzzy pages
to the kernel after one second instead of ten, and enable background decay
threads so purging occurs asynchronously without stalling Ruby request threads.

## Breakdown of runtime asset bytes and container serving

Static assets in `/rails/public` are served directly by Puma with one-year immutable caching rather than an external CDN, making asset reduction a direct saving in image transfer, storage layers, and browser network payloads.

The historical 208 MB baseline was dominated by unstripped source maps (~140 MB across 1,700 files), stale build directories (~35 MB), and layer duplication from post-copy recursive file ownership changes. Modern builds purge source maps when Sentry secrets are exported, reducing the clean Vite output to ~2.7 MB of JavaScript and ~140 KB of stylesheets.

Runtime asset serving is handled by Rails through `ActionDispatch::Static` with `Cache-Control: public, max-age=31536000, immutable`. Only user audio files are offloaded to cloud storage (`SWAY_GCS_BUCKET_ASSETS`), so web application scripts, stylesheets, icons, and fonts reside directly in the container image and are fetched from Puma.

Because `import.meta.glob` in `application.tsx` previously matched all files under `../pages/**/*.tsx`, 24 test suites and Vitest runtime dependencies leaked into production bundles and were eagerly downloaded by the service worker precache. Restricting the glob to exclude `__tests__` directories and `*.test.tsx` files eliminated ~340 KB of JavaScript and prevented test runners from reaching visitors.

Pruning unreferenced static assets — including legacy login bubbles (1.17 MB), abandoned gamification awards (1.68 MB), unused UI mockups (402 KB), an unreferenced web font (517 KB), and duplicate Sprockets images (180 KB), alongside replacing an uncompressed 308 KB bitmap favicon with a 1.5 KB PNG-based icon — removed ~4.7 MB of permanent waste from git tracking and container images.
