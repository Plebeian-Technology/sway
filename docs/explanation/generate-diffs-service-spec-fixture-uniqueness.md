---
mode: explanation
summary: "Why spec/services/generate_diffs_service_spec.rb's bill-fixture helper counts release-date offsets instead of picking a random day."
status: agent-extracted
related: []
---

# Why the diff-spec bill fixture counts offsets instead of picking a random day

`bills` carries a UNIQUE index on `(scheduled_release_date_utc,
sway_locale_id)`. `GenerateDiffsServiceSpecHelpers` used to pick a random
day out of 365 for each fixture bill, and a random day out of 365 let two
bills in one run draw the same date (the birthday problem) and fail with
`RecordNotUnique` about one run in N.

`@release_date_offset` is a module-level counter instead: it makes every
bill this helper creates take the next day, so the collision can't happen
at all.
