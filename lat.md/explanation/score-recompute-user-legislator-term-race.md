---
lat:
  mode: explanation
---

# Why recompute_user_legislator! uses find_or_create_by!

`ScoreRecomputeService.recompute_user_legislator!` is the one place in the service that uses `find_or_create_by!` instead of `create_or_find_by!` (see [[docs/explanation/score-recompute-service-overview.md|the service overview]] for why every other method uses the latter).

The reason is a uniqueness check in the model.

`UserLegislatorTermScore` is the only score table that validates uniqueness in Ruby as well as in the database — the Ruby check is kept because tests inspect `.errors` on an unsaved record. `create_or_find_by!` tries the `INSERT` first and only catches the database's own duplicate-key error; it does not catch a validation failure. When the row already exists, which is the normal case here because an earlier recompute in the same job created it, the Ruby validation therefore blows up before the rescue can help. `find_or_create_by!` looks first, so the usual already-exists path never touches the validation.

## The race window this leaves, and why it is safe

`find_or_create_by!` does leave a tiny window where two processes could both try to create the row. That cannot happen here because only one job per bill and legislator runs at a time.
