---
lat:
  mode: explanation
---
# Comments and where why-content lives

Sway's source carries almost no prose. A why-comment is documentation in the wrong place — it becomes a `lat.md/` section, and the source keeps only a bare `@lat:` pointer to it.

## What a comment is allowed to be

A comment states a bare fact — an `@lat: [[section-id]]` pointer, or a single
clause naming a unit, a bound, or what `nil` means.

There is no length limit on how much reasoning moves out of the
code; the comment itself stays one line either way. The test is not length
but whether the comment explains *why*.

Anything giving a reason, a trade-off, a rejected alternative, a constraint or
an invariant's rationale is documentation. It becomes a section (new, or an
addition to an existing one) in the matching `lat.md/{tutorials,how-to,
reference,explanation}/` file, verbatim where reasonable, classified with the
`diataxis` skill.

Comments that narrate what the code does are deleted rather than moved. If a
reader could reconstruct the comment from the code, it carries no information
and costs a maintenance obligation.

Two tests decide a borderline case: could a stranger who has never seen the
code write this comment just by reading the lines around it? If yes, delete
it. Otherwise, does it sit at a different level than the code — lower for
precision (a unit, a bound, who owns a resource) or higher for intent (the
why, the rejected alternative)? A comment at the same level as the code
restates it.

## Why the rule is this strict

The reason is the readership. This codebase is read mostly by agents working
from grep and partial file reads, and a drifted comment misleads that reader
far more reliably than a missing one does.

A contradiction between a comment (or its linked `lat.md/` section) and the
code it describes is therefore classed as a defect, fixable in the same
commit that changed the code — the same standard applied to a failing
assertion rather than to a style preference.

Measured evidence points the same way: misleading comments dropped LLM
fault-localization accuracy to 24.6% in one 575,000-task study
(arXiv:2504.04372), the worst mutation tested — worse than misleading
variable names — while correct, complete docstrings bought no significant
improvement in code understanding (MITRE, arXiv:2404.03114). Getting a
comment right buys little; getting it wrong costs a lot, which is why the
rule is subtractive rather than additive.

## Where why-content lives now

`lat.md/` is organized by the four Diátaxis modes — `tutorials/`, `how-to/`,
`reference/`, `explanation/` — and a why-explanation is written as a section
in whichever of those fits, dedupe-checked against existing sections first.

A comment that used to run long enough to need its own doc now becomes a
`lat.md/` section instead; there is no separate generation step and no
frontmatter to keep current by hand, because `lat check` validates the graph
directly.

An `@lat:` line in the source is the link from a call site to its reasoning.
Following one is how a reader gets from a line of code to the argument
behind it. Test specs use the same mechanism with `require-code-mention:
true` sections — see the `lat-md` skill for the syntax.

## Which way a reference points

Work is tracked in a private issue tracker, and the reference runs one way: an
issue names the `lat.md/` sections and the files its work landed in, while code
and `lat.md/` name neither the tracker nor an id.

A private id resolves for nobody outside the tracker, so a citation of one
gives a reader no way to check the claim it supports. A section name resolves
for anyone holding the repository, `lat check` reddens when it stops resolving,
and it survives a move to a different tracker.

The tracker keeps the reverse pointers, so a maintainer with access still has
the trail from a change back to the discussion that produced it, and nothing in
the tracked tree depends on that access.

A scanner keeps ids from coming back. `TrackerIdScanner` walks `git ls-files`
and reports every committed line carrying the id shape, and
`spec/config/tracker_id_scanner_spec.rb` reddens on any hit the tree has not
vouched for. It is the third of a family — `EnvCredentialScanner` and
`PersonalDetailScanner` are the others — sharing their split between every
finding and the unvouched ones, so an accepted hit stays visible rather than
vanishing into a skip list.

Two ignore files name a local notes file whose name has the id shape, so those
paths are exempted with that evidence recorded beside them rather than skipped. The scanner assembles its pattern from pieces at run time,
which is why it is never a hit against itself, and it reports a path, a line
and the id alone — never the text of the line, which on a settings template is
content a guard has no reason to quote back.

The pattern is deliberately no wider than the tracker's own id shape. A
lowercase `sway-` prefix names storage buckets and service slugs throughout the
repository, and `SWAY-V170-PRESEED` is a bill fixture rather than a citation,
so a case-insensitive sweep would report all of them and the guard would read
as noise.

## The legacy docs index and its generator

`docs/index.md` lists every file under the four `docs/` mode directories, and it is generated from each file's frontmatter rather than written by hand.

The generator used to be an agent plugin installed on one machine. It went missing, and its absence was indistinguishable from "nothing changed": the plugin exited 0 on failure, so five documents — three of them load-bearing explanations — sat unlisted for weeks while the index looked healthy.

`Sway::DocsIndex` now holds the format and `bundle exec rake sway:docs:index` rewrites the file, so the generator travels with the documents it describes and cannot be missing from a checkout. `spec/lib/sway/docs_index_spec.rb` compares the checked-in file against what the generator produces, which turns an unlisted document into a red gate rather than a silent gap.

A document the generator cannot describe — no frontmatter, no heading, no summary — stops the run and names itself, because the alternative is the failure this replaced.

## The formatter pragma no tool read

A block comment holding `@format` sat at the top of 224 frontend files and 65 legacy ones. Nothing read it, and its presence recorded where a file had been copied from rather than anything about the file.

The pragma is Prettier's: `--insert-pragma` writes it, and `--require-pragma` then formats only the files carrying it. Sway has never run Prettier — no config, no dependency, no script — and oxfmt takes its scope from `pnpm fmt` over the project, not from a marker inside a file.

That leaves a comment a reader cannot act on and a formatter never consults, which is the same class as narration: deleted rather than moved. The 222 remaining copies went in `3c62412c8`.

`app/frontend/__tests__/formatHeader.test.ts` walks the frontend and the mobile app and reddens when a pragma reappears. Its pattern is built from a string rather than written as a literal, so the gate does not match its own source. `mobile/keys/` is outside the walk because it holds credentials nothing needs to read.

## Retired legacy DOCREF comments

Comments of the form `DOCREF <path> <tags>`, pointing into `docs/`, predated this rule and have been retired in favor of `@lat:` pointers into `lat.md/`.

`docs/{reference,explanation,how-to,tutorials}/` stays in place as read-only legacy content so existing documents keep serving readers who land on them directly, while all source code references point to `lat.md/` sections via `@lat: [[section-id]]`.
