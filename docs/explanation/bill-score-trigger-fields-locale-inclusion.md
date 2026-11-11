---
mode: explanation
summary: "Explains why SCORE_TRIGGER_FIELDS is a shorter, different list than VOTE_TRIGGER_FIELDS and why it must include sway_locale_id."
status: agent-extracted
related: []
---
<!-- vale Vale.Spelling = NO -->

# Why the score trigger fields list includes the locale

`Bill::SCORE_TRIGGER_FIELDS` and `Bill::VOTE_TRIGGER_FIELDS` look like they
should be the same list. They are not, on purpose. Do not reuse one for the
other.

`VOTE_TRIGGER_FIELDS` decides when to fetch legislator votes again. That only
needs to happen when identity or vote-timing columns change. Score
recalculation is a different concern with a different trigger: it also needs
to fire when `sway_locale_id` changes, because scoring reads the locale to
choose which theoretical maximum to score against
(`LOCAL_THEORETICAL_MAX` for a city bill, `FULL_THEORETICAL_MAX` for
Congress).

## What went wrong without it

Before `sway_locale_id` was added to `SCORE_TRIGGER_FIELDS`, moving a bill
to a different locale left its newest score row holding numbers computed
under the OLD locale. This happened twice, in opposite directions:

- Moving a bill from Congress to Baltimore left a fabricated `controversial`
  badge on it — the score had been computed against the wrong (higher)
  maximum.
- Moving a bill from Baltimore to Congress left it permanently under-scored,
  until some unrelated change triggered a recompute.

Both cases trace back to the same gap: a locale change is a scoring input,
but it was not on the list of fields that make scoring run again.

## Why both lists use after_commit plus saved_change_to_attribute?

Both `VOTE_TRIGGER_FIELDS` and `SCORE_TRIGGER_FIELDS` are checked with
`after_commit ... if: -> { FIELDS.any? { |f| saved_change_to_attribute?(f) } }`
rather than a `on: :update` callback scoped some other way, because Rails
offers no built-in way to attach an update callback to only particular
columns — the field list and the `saved_change_to_attribute?` check are
how each callback narrows itself to the columns it actually cares about.
