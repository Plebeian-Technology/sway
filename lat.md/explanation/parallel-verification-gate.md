---
lat:
  mode: explanation
---
# Running the whole gate at once

`dip run verify` starts fifteen lanes together instead of running the same checks one after another. Its shape — what runs first, how each lane is invoked, how wide the worker pools are — was settled by measurement.

The lane inventory itself, and what each lane covers, is in [[verification-gates]]. This page is the reasoning behind the arrangement.

## What running the lanes at once saves

Running the lanes concurrently finishes the gate in roughly half the wall-clock time of running the same checks one after another.

The critical path is the install and build barriers, plus the longer of the browser rspec lane and the longest host lane, plus steep. A prediction built from that path matched the measured total closely. The rbs collection install runs between the dependency install and the build as a barrier of its own, and it adds to that path.

## Why the environment shim runs before any lane

`scripts/dip/secrets-root.sh` is the first thing the gate runs, because every lane below it inherits what that script exports.

A linked worktree carries tracked files only, so none of the `.env` files are there and compose refuses to start; the script points compose at the main checkout's copies rather than copying keys into the worktree. What else that arrangement costs a worktree is in [[verification-gates#Known traps]].

## Why some lanes bypass dip compose run

`dip compose run` hands its argument line to a second shell, which re-splits an already-glued line and re-reads `$ ; " ' * [ > |`.

"Drops `-e` flags" was the earlier framing of that same defect and is the wrong one: nothing is dropped, the line is taken apart again. The rake tasks behind `rspec-browser`, `rspec-nonbrowser` and `rake-gates` take a `sway:test:lane[...]` argument holding exactly those characters, so those three lanes — and every printed rerun carrying a `-e` flag — go through `docker compose` directly. `tessdata-parity` passes no such argument and uses `dip compose run`.

`vite.config.ts`'s own `buildDir: ... || undefined`, added since, already turns an empty `SWAY_VITE_BUILD_DIR` into "unset" before rails-vite-plugin's `??` sees it, so that half of the original worry no longer applies. The argument-splitting reason stands on its own.

## Why the JS worker pools are capped

vitest and mobile jest each start a worker pool of roughly cores-1, which oversubscribes the machine inside a fifteen-lane gate; both are capped at two workers, which makes the whole gate faster.

The cap makes its own two lanes slower and every other lane faster, because the uncapped pools starve the rest. Uncapped runs also timed out in tests that pass alone, which is the contention the cap removes.

Memory does not constrain the choice either way, and the host pools' own memory use is not sampled.
