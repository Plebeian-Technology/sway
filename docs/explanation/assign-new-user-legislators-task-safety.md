---
mode: explanation
summary: "Why the sway:assign_new_user_legislators rake task asks for confirmation and switches each user's UserLegislator links off during that user's own turn, rather than deactivating every link up front."
status: agent-extracted
related: []
---

# Why `sway:assign_new_user_legislators` asks for confirmation, one user at a time

`sway:assign_new_user_legislators` rewrites who represents whom, and it
used to be dangerous. It carried a `desc` line, so it showed up in the
task list and could be run by accident, and nothing asked for
confirmation. It also switched EVERY `UserLegislator` to inactive up
front, then walked users one at a time calling external geocoding APIs.
So one mistyped command, or one API failure partway through, could leave
every user with no representatives at all.

The fix asks for confirmation first, and switches each user's links off
during that user's own turn, wrapped in a rescue so one failure cannot
take the rest down.
