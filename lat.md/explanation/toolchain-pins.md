---
lat:
  mode: explanation
---

# Toolchain pins

Three files name the Node version this repo runs on, and different tools read different ones.

They have to agree, and each has to name a version somebody chose. The failures that follow from disagreement read as application defects rather than as environment drift, which is what makes them expensive.

## Which file answers depends on the tool

No single file is authoritative, which is the whole difficulty.

`mise` reads `mise.toml`, and so does every `mise exec` and every mise-managed shell. `nvm`, `fnm` and GitHub's `setup-node` action read `.node-version`.

When `mise.toml` says `"lts"` and `.node-version` says `v24.19.0`, the two name different interpreters, so a test can pass for one person and fail for another with nothing in the code different. `mise which node` can resolve to a different version than `.node-version` asked for, and a Vitest run goes through the first.

`mobile/.node-version` is the third. A file nothing reads can drift from the root while the mobile CI lane runs a floating major — three interpreters for one repo, none of which the pin check could see — so the mobile workflow reads it.

## Why a moving alias is refused

`"lts"`, `"latest"` and a bare major all resolve to whatever is current on the day, so the gap between the files widens on its own without anyone editing anything.

The next widening can cross a major version, where the failure stops being cosmetic. An accepted pin matches `\A\d+\.\d+\.\d+\z` — a version somebody chose.

## Why the frontend suite refuses to start under the wrong Node

Everything under `node_modules/.bin` starts with `#!/usr/bin/env node`, so the interpreter that runs the frontend suite is whichever one `PATH` resolves first.

That might be a Homebrew copy, an nvm leftover, or a CI runner's own service environment. Nothing about the invocation says which one answered.

The resulting failure is quiet rather than loud. Under Node 26, examples fail with `window.localStorage is undefined`. Node 26 declares `localStorage` on `globalThis` where Node 24 does not, so jsdom finds the global already present and installs none of its own. Read from the failures alone this looks like a regression in `CollapsiblePanel`, `useLogout`, `useNewBillInitialValues` and `BillCreatorPipelineLlm`. They pass under the pinned version, so none of it is an application defect.

### Why the guard names every pin file, not just the one it compares against

The guard's value is diagnostic, so it reports the whole pin set rather than the single file it measures against.

An earlier version read only `.node-version` and named only that file, which meant an edit to `mise.toml` produced an abort message pointing at the innocent file — the reader saw `pinned 24.19.0 (.node-version)` and no hint that a different file had moved.

Disagreement is reported even when the running interpreter happens to match one of the pins, because that state is a latent version of the same bug: it is correct only for whoever's tool reads the file that happens to be right.

### Why the check runs before the workers start

Vitest's `globalSetup` runs once, ahead of the worker processes that load `setupFiles`.

The check needs that timing to stop the whole run a single time rather than fail inside every worker, and to catch a bare `npx vitest` invocation that never goes through the package script.

The pins are read relative to the working directory, which `vitest.config.ts` already anchors its aliases to — the suite is a run-from-the-repo-root arrangement either way.

## Why the dockerfile gates read every file and then read the running library

Two lint tasks keep the images in step: one compares what the dockerfiles
install, the other compares what is actually loaded.

The development dockerfile (`.dockerdev/Dockerfile`) and the PDF extractor
dockerfile (`ops/pdf-extractor/Dockerfile`) name the same OCR language packages
differently — Debian prefixes them one way and installs into one directory,
Alpine prefixes them another way and installs into another — so adding a
language to the development image without adding its differently-named twin to
the extractor image leaves the two reading different languages with nothing to
say so. The task reduces both files to a plain set of language codes, fails
when the sets differ, and verifies that `docker/dockerfiles/production.alpine.dockerfile`
carries no `mupdf-tools`, `tesseract-ocr`, or `TESSDATA_PREFIX` declarations
now that PDF extraction runs outside the Rails image.

Which files it reads is the part that was wrong for a long time. It compared
production against a dockerfile that built no image at all: that file's final
stage was commented out and nothing referenced it but the task, so the image
that does the work was free to drift while every run reported a pass it had not
earned. The file was deleted; the lesson is that a hand-picked pair of paths is
the failure, so the SQLite gate globs every dockerfile in the repository
instead, which also covers a new one the day it is added.

The SQLite options matter for the same reason and one more. The gem is pinned
to compile the copy it vendors, so those options reach the database engine that
serves requests; setting them in one dockerfile and not the other means
development and production run different SQLite, which is the state the gate
was written to end. Two options in the obvious list are unsafe here and neither
announces itself — one builds cleanly and kills the container at boot, the
other quietly changes what a rebuilt database looks like to the replicator — so
the forbidden list carries a reason for each and the task prints it rather than
only naming the option.

A third task reads the SQLite loaded right now, because a dockerfile only
governs a machine that builds through Docker. CI does not: it runs on a host
toolchain, so nothing it does passes through a dockerfile. The belief that CI
followed automatically was wrong and invisibly so — every dockerfile agreed,
the gate passed, and CI went on compiling the old options because the gem was
already built and nothing rebuilds a gem that is already there. A gate that
reads only source files cannot see that.

What the runner does about it follows from the same fact: a check first, and a
rebuild only where the check disagrees, because installing gems leaves an
already-built one alone and a rebuild compiles SQLite from source rather than
fetching it. The options themselves are read out of the production dockerfile
instead of being written a second time in the workflow, so a machine that never
builds through Docker still follows the one place they are set, and
[[production-image#Why the SQLite options are written as local bundler configuration|where the images write them]]
stays the only place a change has to be made.

## Why Ruby and Python are exempt from the same check

The `ruby` and `python` entries in `mise.toml` are deliberately outside it.

Ruby is pinned by `.ruby-version`, and `mise.toml`'s `ruby` entry says `latest` rather than a version, so there is no second number for the check to compare it against. Whether a machine's shims really resolve that pin is settled at the machine instead, in [[continuous-integration#What a continuous-integration run assumes about its machine#Why the runner's Ruby comes from the host toolchain#Why the shim directory is proved before it is trusted]]. Python has no second file to disagree with either.

## Why no workflow writes the version inline

A workflow that writes the version inline is invisible to a pin-agreement check, which is how the mobile lane sat on major 22 unnoticed.

`spec/config/node_version_pin_spec.rb` asserts that no `.github/workflows/*.yml` file writes `node-version:` inline, so every workflow reads a pin file and nothing is kept in step by hand.
