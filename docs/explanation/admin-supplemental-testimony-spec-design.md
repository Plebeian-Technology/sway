---
mode: explanation
summary: "Why spec/system/admin_supplemental_testimony_spec.rb pins pasted testimony turning org positions back on, and the queued-job race and fixture choices it depends on."
status: agent-extracted
related: [stale-change-detection.md]
---

<!-- vale Vale.Spelling = NO -->

# spec/system/admin_supplemental_testimony_spec.rb design notes

## Why "turns org positions back on after testimony is pasted in" exists

Hands-on testing found the assertion this file was missing: the
other examples around it cover entering testimony, keeping it, and sending
it along with a regeneration, but not one of them says positions come
BACK. That is the whole point of this example — the bill starts with no
draft org positions, because the positions call is skipped entirely on a
bill with no testimony, and pasting some is what turns it back on. The
fixture pastes one sentence about renters and expects exactly one draft back,
naming the group and its stance.

## Waiting for "Queued…" before running the job queue

The regenerate click sends the request and returns; the job is enqueued
inside that request. `perform_enqueued_jobs` run immediately after the
click can find the queue still empty, so the job runs later or never and
the example fails with "no matches" for a card whose absence has nothing
to do with positions — measured happening on the first run of this
example. Waiting for the status badge to say "Queued…" first closes that
gap. `spec/system/admin_summary_stale_marker_spec.rb` hit the identical
race and fixed it the same way.

## Why the fixture's organization name keeps its punctuation

The org-position card's id lower-cases the organization name and replaces
RUNS OF WHITESPACE only, so a `/` in the name survives into the id.
Keeping the fixture's organization name ("r/baltimore Reddit
community") rather than a tidied one is deliberate: names with punctuation
are ordinary, and a fixture that avoided them would leave the id rule
untested.
