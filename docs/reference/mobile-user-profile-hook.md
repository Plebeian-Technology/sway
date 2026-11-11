---
mode: reference
summary: Contract for useUserProfile — why it narrows the bootstrap payload's current_user instead of screens reading it directly.
status: agent-extracted
related: []
---

# useUserProfile hook

`useUserProfile` (`mobile/src/hooks/useUserProfile.ts`) is the signed-in
person's own details, in one place.

The startup payload already contains `current_user`. This hook pulls that
out, gives it a precise type, and adds a couple of worked-out flags, so the
profile screens do not each have to dig through the payload themselves.

## Why not read the startup payload directly?

- The profile screens want one typed `user` object to work with.
- "Is anyone signed in?" is `useSession`'s job. This hook is about the
  saved details, not about being signed in.
- Doing the narrowing here means that if the startup payload's shape ever
  changes, only this file has to change.
