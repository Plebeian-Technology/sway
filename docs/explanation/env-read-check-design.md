---
mode: explanation
summary: "Why EnvReadCheck walks Ruby's parse tree instead of grepping, and how it decides which files under app/ it can see."
status: agent-extracted
related: []
---

<!-- vale Vale.Spelling = NO -->

# Why EnvReadCheck parses instead of searching

`EnvReadCheck` refuses any read of `ENV` anywhere under `app/`, with exactly
one allowed path: the credential door, `app/lib/env_secret.rb`.
Everything before this class moved the names credentials live under; nothing
before it stopped a new bare `ENV` read from landing. This is what stops the
fifty-fourth read from being added the day after the settings work declares the other
fifty-three.

## It parses rather than searches

A text-shaped sweep already missed a live credential read in this repository
once. `spec/support/env_credential_scanner.rb`'s own header records it: a
read in a `.yml` file that `grep 'ENV\[' --include='*.rb'` could not see,
because the sweep only looked at `.rb` files at all. The spec written beside
that sweep inherited the blind spot exactly — one example per site the sweep
found, so a site it could not see had no example, and a missing example
looked exactly like a clean result.

Walking the syntax tree Ruby ships in its own standard library (Prism)
instead of matching text closes that gap by construction rather than by a
rule someone has to keep true. A comment is not a node in that tree, and a
string literal is not a constant, so neither `# ENV["X"]` nor `"ENV[\"X\"]"`
produces a `ConstantReadNode` or a `ConstantPathNode`. A line comment, a
block comment, and a string holding the same word are all excluded, with no
extra logic asked to remember to exclude them.

## Which files it looks at

`EnvReadCheck` chooses files the same way `EnvCredentialScanner` does
(`spec/support/env_credential_scanner.rb#scannable_paths`): via `git
ls-files`, not `Dir.glob`. An untracked scratch file dropped under `app/` —
deliberately, to test this class, or by accident — must never be able to
fail a check that runs on every push.

## Why it stays plain Ruby

`EnvReadCheck` needs no database and no Rails boot, so the rake task
wrapping it (`lib/tasks/sway_lint.rake`) carries no `:environment`
dependency.

## Mapping ERB and Prism edge cases back to a real line number

`#offences_from_erb` compiles a template with `ERB.new(...).src` before
scanning it, and reports the finding at `line - 1`. ERB's standard-library
compiler inserts one `#coding:` line ahead of the translated source and
otherwise keeps the raw file's own line count — it pads multi-line raw text
runs with blank lines to keep backtraces aligned. This was verified
empirically against this repository's own templates before being relied on:
a bare tag, an output tag, several raw lines of HTML with no tag between
them, and a call spread over two lines all compiled to exactly one line
higher than the line the read sits on in the raw `.erb` file, with no
exception found. Mapping back to the raw line, rather than reporting the
compiled one, means a finding in a template names the line a human editing
the `.erb` file would actually go to — reporting it one higher, unremarked,
is a mistake this check's own research caught once already.

One of those templates, `app/views/layouts/application.html.erb`, compiles
to source that is invalid Ruby at the top level — a bare `yield` is only
valid inside a method body — so `Prism.parse(...).success?` is false for it.
That does not stop `#lines_with_env` from working: Prism's parser recovers
from a syntax error and still returns a best-effort tree rather than
raising, and the visitor walk still completes and still finds every `ENV`
node elsewhere in the file. This check never needs a template's compiled
source to be valid standalone Ruby, and never boots anything to find out.

## Which extensions count as Ruby source

`RUBY_LIKE_EXTENSIONS` (`.rb`, `.builder`) are parsed directly; `.erb` is
handled separately (above). Attempting to parse a binary or a non-Ruby file
as Ruby source could only ever error, never find a read, so the guard's own
shape argument (cover `app/` by shape, not by a list of names) is
about variable spellings, not about trying to parse files that were never
going to hold one.

`NON_SOURCE_EXTENSIONS` (image and font formats) are excluded outright and
never surfaced via `#skipped_paths`, because those formats can never hold a
Ruby ENV read — attempting to parse one as Ruby source could only ever
error, never find one. Anything else this check does not recognize (a
`.rake` file, a `.jbuilder` view, `app/assets/config/manifest.js`) is
reported through `#skipped_paths` instead of joining that list, so a
newly-added extension shows up in CI output rather than vanishing the way a
text sweep already missed a real read once (see above).

## Why a missing allowed path raises instead of passing

`MissingAllowlistedPathError` is raised when a path in `ALLOWED_PATHS` no
longer exists on disk. A renamed guarded file has already silently
switched a check off in this repository once, and the switched-off check
still reported green. Reporting zero offences here would be that same
failure again wearing a different shape, so this is checked first, before
any file is scanned, and with its own message naming the missing path
rather than folding into a report of "nothing found".

## The forms `EnvConstantVisitor` catches

A comment is not a node in Prism's tree and a string literal is not a
constant, so neither `# ENV["X"]` nor `"ENV[\"X\"]"` produces a
`ConstantReadNode` or a `ConstantPathNode` — both false alarms are excluded
by construction rather than by a rule.

`ConstantReadNode` catches the bare form (`ENV["X"]`, `ENV.fetch(...)`,
`ENV[some_var]`, an interpolated key, `ENV.to_h`, `ENV.each`,
`ENV.dig(...)`, `ENV.key?(...)`); `ConstantPathNode` catches the explicitly
top-level form (`::ENV["X"]`), which Prism parses as a different node
entirely. Both were run against all ten spellings this check's design lists
before this class was relied on; each produced exactly one hit, on the line
the constant itself starts on, so a call spread over several lines whose
first line is the bare word alone is reported on that first line, matching
where a reader's eye actually goes.

## Why `#offences` includes the allowed path

`#offences` deliberately does not filter out the one read at the allowed
path. Keeping it IN the list is what lets a caller prove there is exactly
one read under `app/` and that it is the right one, rather than only ever
proving "none that this scan happened to look for" — which passes
identically whether the scan is thorough or broken.

## Why a name in `#skipped_paths` is not a failure

A name landing in `#skipped_paths` is exactly the gap this check cannot see
through, made visible instead of silently letting it pass.

## Why `#skipped_paths` must be called after `#offences`

`#skipped_paths` is populated as a side effect of `#offences`, so call
`#offences` first — it resets this list on every call.

## Why `SWAY_TEST_DATABASE_DIR` and `TEST_ENV_NUMBER` live in `lib/`, not `app/`

`Sway::LegislationTestIsolation` (`lib/sway/legislation_test_isolation.rb`)
reads `SWAY_TEST_DATABASE_DIR` and `TEST_ENV_NUMBER` directly from `ENV`.
They are harness plumbing, not one of the eight names
`Sway::Settings::Legislation` declares — they are never
set outside an isolated rspec invocation, so declaring them as an
application setting would be wrong.

They live in `lib/`, rather than beside the reading in
`app/services/legislation/paths.rb`, because `lib/` is the one directory the
app-wide ENV guard (68-11, this class) does not cover — the same
reason `app/lib/env_secret.rb` needed an explicit exception and this needs
none. The two harness-owned reads had to be reconciled with this guard, and
that extraction was the resolution: the guard's allowlist stays
at exactly one path rather than growing a second entry for a value no
operator sets.

## Why the real-app example asserts a nonzero count, not just zero offences

The point of the whole guard is that an example asserting only that the
real `app/` has zero offences passes identically whether the scan is
working or silently broken and finding nothing.
`spec/lib/env_read_check_spec.rb` instead asserts a
specific, known, nonzero result — exactly one offence, at the credential
door, on the one allowed path — so a scan that stops finding anything
fails this example rather than passing it by accident.

## Why `sway_lint_env_reads_rake_spec.rb` stubs `EnvReadCheck.new` for its failure-path examples

`EnvReadCheck` itself (`lib/env_read_check.rb`) is thoroughly covered by
`spec/lib/env_read_check_spec.rb`. `spec/lib/tasks/sway_lint_env_reads_rake_spec.rb`
covers the rake wrapper CI actually calls (`lib/tasks/sway_lint.rake`) —
specifically its `disallowed = offences.reject { |o|
check.allowed_paths.include?(o.path) }` filtering and the abort wiring,
neither of which lives in `EnvReadCheck` itself.

Its failure-path examples stub `EnvReadCheck.new` rather than planting a
real disallowed read under `app/`: `EnvReadCheck#scanned_paths` reads `git
ls-files`, so an untracked scratch file would never be scanned, and
`git add`-ing one purely for a test is worse than a double.

## Why a spec plants a read under lib/ and asserts it stays invisible

The scan being scoped to `app/` only (see above) is a real escape hatch,
not a hypothetical one: `lib/sway/legislation_test_isolation.rb` reads
`ENV` directly today. `spec/lib/env_read_check_spec.rb` plants
a second ENV read under a temporary `lib/` and asserts the scan does not
see it, pinning that fact against the live file. A future refactor that
moves the read into `app/` — or that quietly adds a second `lib/` reader —
has to touch this spec, instead of the escape hatch growing invisibly.
