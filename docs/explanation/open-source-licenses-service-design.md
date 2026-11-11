---
mode: explanation
summary: "Explains why OpenSourceLicensesService covers only frontend npm packages (not Ruby gems), why it filters to direct, non-MIT dependencies, and why it degrades to an empty list on a bad snapshot."
status: agent-extracted
related: []
---
<!-- vale Vale.Spelling = NO -->

# Why OpenSourceLicensesService is scoped the way it is

`OpenSourceLicensesService` builds the open-source attribution shown on
the public `/licenses` page.

## Scope: frontend packages only

Third-party packages bundled into Sway's *frontend* are in scope. Their
code ships in the Vite bundle served to every browser — that is
distribution, so the MIT/BSD/Apache clauses about keeping license notices
apply. Ruby gems are deliberately NOT listed: they run only on the
server, are never shipped to users, and so carry no notice obligation
(the one license family that would still apply — AGPL, which treats
serving over a network as distribution — is absent from the Gemfile).

## Two filters narrow the list to "licenses worth a look"

- **Direct dependencies only** — the package.json `dependencies` block.
  This filter runs when the snapshot is built, in `rake
  sway:licenses:frontend`, because `package.json` exists in the Docker
  build stage but not in the runtime image.
- **Non-MIT only** — applied in `#javascript_dependencies`. MIT is the
  boilerplate permissive default; hiding it surfaces the packages whose
  terms actually differ.

## Why the source is a pre-built snapshot, not a live scan

The source file is `config/oss-frontend-licenses.json`, a cleaned
snapshot generated at image-build time — pnpm does not exist at runtime.
A missing or malformed snapshot degrades to an empty list rather than
raising.

## Why the is_a? guards exist twice over

The `is_a?` guards on the parsed JSON do two jobs: they harden against a
malformed snapshot, and they keep the untyped JSON flowing cleanly through
Steep, the RBS type checker (`Array()` on an untyped value widens to the
bottom type).

## Why each dependency is a plain Hash

Each dependency is a plain `Hash {name:, version:, license:, homepage:}` —
directly Inertia-serializable, no wrapper object.
