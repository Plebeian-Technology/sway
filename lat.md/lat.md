---
lat:
  require-mode: true
---

# Sway

Sway is a civic engagement platform where people vote on the same legislation their elected representatives vote on, so the two records can be compared. It runs as one Rails + React monolith serving three jurisdictions.

This directory is the knowledge graph for that system: what it does, and why it
is built the way it is. It is organised by the four Diátaxis modes, the same
split the much larger `docs/` tree uses.

- [[tutorials]] — guided walkthroughs for someone new to the codebase
- [[how-to]] — recipes for tasks that recur
- [[reference]] — neutral maps of the machinery
- [[explanation]] — the reasoning behind the design

## Where to start

A reader new to Sway should read the explanation of the system's shape first,
then follow one vote through it.

[[system-shape]] first, then [[trace-a-vote]]. After that, [[domain-entities]]
is the map to keep open while working, and [[naming-decisions]] is what to
check before naming anything new.

## What lives here and what lives in docs/

`lat.md/` is where every code comment's reasoning lives — a why-comment
becomes a section here, referenced from source by a bare `@lat:` pointer.

`docs/` is a separate Diátaxis tree that held that role earlier; its
mode directories remain in place as read-only legacy content while all source
pointers now resolve through `@lat:` into `lat.md/`. See [[comments-and-docs]].

Every document belongs in exactly one of these.

- [Tutorials](tutorials/tutorials.md) — Guided first passes through this system, each ending somewhere the reader can see.
- [How-to](how-to/how-to.md) — Recipes for tasks that recur, written for someone who already knows what they want.
- [Reference](reference/reference.md) — Lookup facts about this system: fields, states, limits, names and defaults.
- [Explanation](explanation/explanation.md) — Why this system is shaped the way it is, and what the alternatives cost.
