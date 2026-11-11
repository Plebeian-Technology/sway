---
mode: explanation
summary: "Explains LegislatorTerm.current's undeclared-locale skip and its departed-member fix, and .covering's successor/predecessor fixes."
status: agent-extracted
related: [legislator-term-write-guard-history, retire-departed-members-safety-design]
---
<!-- vale Vale.Spelling = NO -->

# LegislatorTerm.current and .covering

## Why scope :current skips a locale with no declared calendar, rather than raising

`LegislatorTerm.current` reads every term across every legislator, so one
undeclared locale would break the legislators page for every locale at
once if it raised. Unsupported locales exist in production already, since
registering a user creates a locale row for their city and state. With no declared calendar, Sway cannot say when the term ran
or claim the person holds office — skipping is the honest answer, not a
workaround. The scope logs a warning naming the locale, for whoever adds
the declaration.

Do not re-implement this locale-branching date math anywhere else; go
through this scope.

## Why `RefreshLegislatorsCacheJob#refresher_for` skips rather than raises

`RefreshLegislatorsCacheJob#refresher_for` walks EVERY locale, so raising
for one locale with no declared refresher would stop the other two —
skipped rather than refused, the same reasoning as `LegislatorTerm.current`
above, which filters and warns over the same shape of scan.

## Why `RefreshLegislatorsCacheJob::REFRESHERS` maps a declared name, not a predicate chain

`REFRESHERS` maps a locale's DECLARED refresher name to the class that
fetches it. This used to map the predicates `congress?`, `regional?` and
`local?`, first truthy one winning. `#local?` IS "neither", so every
locale that is neither got `BaltimoreRefresh` — including the eleven
registration creates for readers' cities, each written to its own roster
path. There is no final else: a locale that declares nothing
is skipped and named in the log.

## Why the departed-member fix uses running_on instead of covering

`TermWindow.covering` only checks that a term has BEGUN. Using it inside
`scope :current` meant a legislator's ended term still counted as
"serving" — departed members kept showing on the legislators page and kept
re-scoring on every vote. `#running_on` checks both ends of the term
window instead, so `scope :current` only picks a term that is both begun
and not yet ended.

`#running_on` returns `nil` when no candidate term covers `date` — a real
"not serving" answer, not an error.

## Why .covering returns nil instead of guessing

`LegislatorTerm.covering(vote_date, legislator:)` can legitimately return
`nil` — that means the person held no office on that date, which is an
answer, not a fault. This reverses an earlier decision that pinned
an unmatched vote to the legislator's earliest term, which had the effect
of scoring a successor on a predecessor's bills.

`.covering` queries `where(legislator_id:)` rather than going through
`legislator.legislator_terms`, so the method does not depend on
`Legislator`'s association surface.

The winner `TermWindow.covering` finds may have ENDED before the vote,
since `TermWindow.covering` checks starts alone. `.covering` re-checks the
end date and discards a term that ended before `vote_date` — without this,
a departed member's last term keeps taking every later bill cast after
they left. This is the other edge of the same fix.

When no candidate term exists at all, `.covering` logs a warning rather
than raising: reaching that branch means a caller asked about a legislator
office type Sway does not track terms for (a mayor or a governor), and
callers that can meet one of those are expected to skip before asking — so
reaching here is a caller's mistake, not a fact about the data.

### What production_migration_spec.rb's term-coverage guard checks

`TermWindow.covering`/`LegislatorTerm.covering` returns `nil` in the two
different cases above, uniformly across environments — no
dev/test-raises-vs-production-fallback split, and no nearest-term fallback
at all. A vote whose date falls outside every term window returns `nil` by
design: that legislator held no office that day, so skipping them is
correct, not a data gap. A legislator with ZERO `legislator_terms` rows
also returns `nil`, but through the different path just described —
`SwayLogging.warn`'s `legislator_has_no_terms` branch, meant for a caller
mistake, not a fact about the data.

`spec/production_readiness/production_migration_spec.rb` guards only the
second case: it asserts every legislator who cast a vote has at least one
term row, so scoring is never silently skipped for a legislator this
codebase never seeded a term for. Against the untracked production-database copy the spec loads,
every legislator who cast a vote has at least one term row, with no
exceptions. The spec loads every term once rather than once per vote, to
avoid thousands of queries against real vote rows.

## Why scope :current is date-derived, and why it group_by's by legislator_id

The `current` set carries no flag column and no `finalized_at` — it is the
date-derived "current" set. For each legislator among the candidates
already in scope, it keeps only the term running today: begun and not yet
ended. `group_by(legislator_id)` keeps this correct both called bare
(`LegislatorTerm.current`, spanning many legislators) and pre-scoped to one
legislator via `Legislator#active_term`'s `has_one ..., -> { current }`.

## Why LegislatorTerm#current? and Legislator#current_district_score are kept though unused

`LegislatorTerm#current?` and `Legislator#current_district_score` have no
callers in `app/` today. Both are kept deliberately as small read-side
helpers: `spec/models/legislator_term_spec.rb` and
`spec/models/legislator_spec.rb` call them directly, to verify the
date-derived "current" set (and the score row it resolves to) is right
under both the bare-scope call shape and the per-instance predicate call
shape.

## Why `RefreshLegislatorsCacheJob` rescues each locale independently

Each locale's refresh is wrapped in its own rescue, so one flaky upstream
source never stops the other locales from refreshing. The rule this job
must not break: rescue each locale, log it, report it to Sentry, and keep
going through the rest of the loop.

`GITHUB_TOKEN` handling and branch-naming security notes for this job's PR
step are documented in `docs/kamal-secrets.md` (GITHUB_TOKEN section), not
here.
