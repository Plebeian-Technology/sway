---
mode: explanation
summary: "Why spec/system/user_voting_spec.rb waits for the 'Vote saved!' toast rather than the vote-recorded marker, the transform() bug that assertion catches, and why voting is also driven on an ordinary bill page."
status: agent-extracted
related: []
---

<!-- vale Vale.Spelling = NO -->

# spec/system/user_voting_spec.rb design notes

## Why the save assertion waits for the toast, not the vote-recorded marker

The "vote recorded" wrapper around the vote buttons appears as soon as the
chosen side is written into the form data — inside `createVote`, before
the request even goes out — so it proves nothing about whether
the vote was saved. The "Vote saved!" toast does: it only appears on
Inertia's success event, after `UserVotesController#create` has saved and
redirected, and it stays up for five seconds. The example waits for the
toast rather than sleeping or trusting the marker.

## The transform() bug this example guards against

The `UserVote` row assertion after a vote guards an old bug: the form
copies its data for sending in a later effect, so calling `setData` and
`post()` in the same handler, without `transform()`, used to send
`support: nil` and validation quietly threw the vote away. The example
checks the persisted row's `support` value directly rather than trusting
the UI alone.

## Why voting is also driven on an ordinary bill page

Voting has to work on an ordinary bill page (`/bills/:id`), not only on
the Bill of the Week. Both pages use the same vote panel — the For and
Against buttons, the "Cast vote" dialog, the vote-recorded marker — but
they are two different pages, and the ordinary one had never been driven
while online: `spec/system/offline_spec.rb` visits it only for its offline
case, and skips when the vote buttons are missing.
