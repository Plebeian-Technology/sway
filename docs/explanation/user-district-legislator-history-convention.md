---
mode: explanation
summary: "Explains why UserDistrict and UserLegislator rows are never deleted, only flipped inactive, and how ReconcileUserDistrictsJob uses that history to tell a user's move apart from a seat changing hands."
status: agent-extracted
related: []
---
<!-- vale Vale.Spelling = NO -->

# Why UserDistrict rows are never deleted

`UserDistrict` is a record of every district a user has ever been assigned
to, kept so the history can be compared over time. Rows are never
deleted — moving a user to a new district flips `active` to false on the
old row instead of adding a duplicate or destroying it, the same
convention `UserLegislator` follows (`find_or_initialize_by`, flip
`active`, `save!`).

`ReconcileUserDistrictsJob` compares the district a user resolves to NOW
against the one stored here, and that comparison is how it tells "the user
moved to a different district" apart from "someone new holds the same
seat" — a distinction that would be impossible to draw at all if the old
row were simply overwritten or deleted rather than kept, inactive,
alongside the new one.
