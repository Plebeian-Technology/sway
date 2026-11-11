---
lat:
  mode: explanation
---

# The open-source licence snapshot

Sway is AGPL-3.0, so the `/licenses` page is an obligation rather than decoration. It renders `config/oss-frontend-licenses.json`, which is written during the image build and exists nowhere else.

## Why the snapshot is read from node_modules

A production build could write an empty snapshot, so the page listed nothing, and two layers of fallback kept it quiet.

The cause sits in the image's own `nodemods` stage: `pnpm licenses list` reads each package's licence out of pnpm's content-addressed store, and the store is not there. It lives under the installing user's home directory in the stage that ran `pnpm install`, and the stage that runs the snapshot copies `node_modules` and nothing else. pnpm then exits 1 with `ERR_PNPM_MISSING_PACKAGE_INDEX_FILE` — and it writes that error to standard output, not standard error, so the only trace in a build log was the task's own one-line warning among several hundred lines.

`Sway::FrontendLicenses` reads the manifests instead: each name in `package.json`'s `dependencies`, resolved to `node_modules/<name>/package.json`, for its version, licence and homepage. Nothing outside the copied tree is consulted, so the snapshot cannot depend on a directory that was never copied, and it cannot change with the floating pnpm version the image installs. Checked against pnpm's own answer in the built image: the same packages, versions and licences.

The licence field is read in all three spellings npm has used — a string, an object with a `type`, and an array of those — because packages in the tree still use each of them.

## Why a failure is now audible twice

A snapshot failure still does not fail the build, because an attribution page is not worth refusing a deploy over. It is no longer silent either.

The task stops with the reason on standard error and names what is missing. Before it stops it writes a stand-in snapshot holding one row, which `OpenSourceLicensesService` renders like any other entry, so the page says the snapshot is unavailable rather than looking like an application that depends on nothing. The build log carries a banner line of its own for a reader scrolling past.
