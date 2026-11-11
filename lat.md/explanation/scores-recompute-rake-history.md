---
lat:
  mode: explanation
---

# sway:scores:recompute_all rake task history

`sway:scores:recompute_all` is the run-once score repair used after a deploy, as the task's own documentation says, and it also runs as part of `dip seed`.

## The term-keyed API fix

The task used to hand a `Legislator` to `ScoreRecomputeService.recompute_legislator!`.

The task used to hand a `Legislator` to `ScoreRecomputeService.recompute_legislator!`, which now expects a `LegislatorTerm`, and called `recompute_user_legislator!` with one argument when it takes two (a `user_legislator` and a `legislator_term`). It raised `NoMethodError` before writing a single row. The spec examples pin that the methods are keyed by term.

## Rebuilding an ended term's row instead of preserving it

The task used to pin that an ended term stayed frozen, and that rule changed later.

The task walked `Legislator.serving` and each person's active term, on the reasoning that a legislator-side row for an old term could not change. Nothing read a past term when that reasoning was written.

The History tab now reads exactly those rows, so a member who has left — whom `.serving` excludes entirely — showed a blank there forever, while the votes that make the number sat in the database all along. The fix rebuilds an ended term's legislator-side row from source on every recompute, and also walks members who have left so their only (ended) term gets a row at all.

### What the departed-member spec checks

`spec/lib/tasks/scores_recompute_rake_spec.rb`'s "repairs a member who has left" example builds two readers on purpose: one who still uses Sway in the member's locale, and one whose link to that member has ended.

`spec/lib/tasks/scores_recompute_rake_spec.rb`'s "repairs a member who has left" example builds two readers on purpose: one who still uses Sway in the member's locale, and one whose link to that member has ended — exactly what the History tab lists. The legislator's own rows count live constituents only, by a rule this change does not touch, so the second reader's vote shows up in their own `UserLegislatorTermScore` row and not in the legislator's `LegislatorLocaleScore`/`LegislatorDistrictScore` rows.

### Why the "no term at all" boundary case needs an old term to rule out

A legislator with NO terms at all has no `active_term` — a mayor or governor, say, who is outside term-based scoring.

The `.serving` scope joins `:active_term`, so it leaves such a legislator out, and the task must neither build a row for them nor raise. The spec's boundary example is careful to give the legislator no term at all, rather than an old, ended one: "current" here means the most recently started term with no end limit, so a legislator whose only term has already finished still counts as serving — an old term alone would not actually test the no-term case.
