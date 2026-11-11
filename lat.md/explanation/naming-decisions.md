---
lat:
  mode: explanation
---
# Naming decisions

Sway keeps one canonical term per domain concept, decided once and recorded in `docs/terminology.md`. The register exists because a synonym is indistinguishable from a second concept to a reader working from grep.

Most of this codebase's readers are agents doing exactly that, which raises the
cost of drift well above what a human-only project would pay.

## One term per concept

The rule has an unusual corollary: there are no going-forward-only renames. A
rule binding only new code would create a third state — the old name, the new
name, and the confusion between them.

So every decided rename migrates the whole codebase, and until it does, the old
name stays put. A name is therefore in exactly one of three states: canonical,
pending migration, or exempt for a stated reason. The pending table in
`docs/terminology.md` is the list of renames that have been decided but not yet
executed.

Internal identifier changes finish before schema and mobile-wire migrations.
The remaining internal families share one epic gate, also required by
duplicate-code extraction, so a completed page rename cannot release work
that still depends on other names moving.

## Two vocabularies, one per actor

Users and legislators *cast votes*, which are For, Against, or Abstain.
Organizations *hold positions*, which are Support, Oppose, or Neutral. The two
sets never mix: an organization does not vote For, and a user does not Support
a bill.

The web and mobile submission hooks are both named `useCastUserVote`. Mobile
controls distinguish `userVote` from `pendingUserVote`; their shared choice
type is `UserVoteChoice`. These are internal names, so they do not change the
stored `support` field or its wire values.

Jurisdiction rules use `publishes_legislator_votes` and
`roster_lists_only_current_legislators`. `RetireDepartedLegislatorsService`
names the actor auditing departures; its existing operational event keys stay
stable for log consumers.

This is a copy-level distinction with a deliberate storage-level compromise.
All three tables — `user_votes`, `legislator_votes`,
`organization_bill_positions` — store `FOR` / `AGAINST` / `ABSTAIN`, and
organization surfaces translate at display time. Renaming the `support` column
would cost a three-table migration plus a mobile wire break, which was judged
not worth it while the display layer can carry the distinction reliably.

## Names that cannot move

Two categories are exempt. Third-party contract names keep whatever the other
side calls them — a Faraday option, a Rails keyword, a React Native prop — and
Sway's own wrapper one layer up carries the unit and context instead.

Frozen wire keys are the other category. `is_admin`,
`org_position_taken`, the `legislation_pipeline_run` prop, and every key pinned
by `spec/requests/serializer_whitelists_spec.rb` are read by a mobile build
that is already in users' hands. Changing one is a compatibility plan, not a
rename. Similarly, public branding presents "Bill of the Month" across web and
native reader surfaces while the retired route `/bill_of_the_week` survives only as a
redirect to `/bill_of_the_month`.

## A route name is not a label

A navigation route is named for the framework's benefit, and the words a reader
sees come from a label rather than from that name.

The mobile profile stack's first screen is called ProfileHub because a route
sharing a name with the tab containing it makes the navigator warn about an
ambiguous target. Renaming the route costs nothing visible: what the reader
sees is unchanged.

## Verbosity beats brevity

Where two names compete, the longer one that says *why* the thing exists wins.
`legislation_pipeline_run` was kept over `pipeline_run` on exactly this ground:
the long form tells a new reader why Sway has a pipeline at all.

The related rule is that any name carrying an amount names its units —
`time_since_introduction_ms`, `vote_date_time_utc`, `byte_size`. A bare number
in a column name is a defect waiting for someone to guess wrong.
