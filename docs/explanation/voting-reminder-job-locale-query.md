---
mode: explanation
summary: "Why VotingReminderJob finds a bill's locale users through active user_legislators rather than user_districts or a district join."
status: agent-extracted
related: []
---

<!-- vale Vale.Spelling = NO -->

# Why `VotingReminderJob` finds locale users through `user_legislators`

`VotingReminderJob` works out who belongs to a bill's locale from ACTIVE
`user_legislators` -> `legislator`, the same shape as `User#districts` /
`User#user_legislators_by_locale`. An earlier join over `user_districts`
selected nobody in production: only the dev seeds ever wrote that table;
`SwayRegistrationService` creates `UserLegislators` only.

Locale scoping uses the `sway_locale_id` column directly on legislators —
not a district join, which would INNER JOIN through `active_term` and
silently drop a legislator with no current term.
