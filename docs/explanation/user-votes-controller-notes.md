---
mode: explanation
summary: "Design notes for UserVotesController: the shared already-recorded message, why #show answers 204 for no vote, the url_from open-redirect fix, cast-vote finality, and the double-click RecordNotUnique race."
status: agent-extracted
related: [docs/explanation/serializer-whitelist-endpoints.md]
---

<!-- vale Vale.Spelling = NO -->

# `UserVotesController` design notes

## Why `VOTE_ALREADY_RECORDED_MESSAGE` is a shared constant

A cast vote is final. This same text backs the mobile error envelope, the
web alert flash, and the Inertia errors payload, so `VotePanel`'s
`onError` fires with a consistent message no matter which surface a
rejected re-vote reaches.

## Why `#show` answers 204, not 200 with `null`

204 No Content is this endpoint's agreed "no vote recorded yet" signal —
callers distinguish "not voted" from "voted" by status code, not by
parsing a null or empty body. This is kept deliberately (not switched to
200 + null) so existing consumers that branch on 204 stay correct. The
response uses `head`, not `render json:` — Rails discards a 204 body
anyway (the `Rails/UnusedRenderContent` cop).

## Why request specs POST support values in capitals

The frontend sends `support` values in capitals (`VoteButtonsContainer.test.tsx`,
`LegislatorVote::Support::FOR = "FOR"`), so `spec/requests/user_votes_spec.rb`
uses that same uppercase form throughout. Fixing the case of a
lowercase value is the model's job, not the controller's: `upcase_support`
runs as a `before_validation` hook, so a lowercase value is capitalized
before the list of allowed values is checked — covered separately in
`spec/models/user_vote_spec.rb`.

## Why `#create` resolves `target` through `url_from` before writing

`url_from` returns `nil` for any `redirect_to` value that points at
another site, so a crafted off-site URL falls back to the bill path. That
fixes two problems at once: a web 500 (`raise_on_open_redirects` would
blow up on the Inertia redirect) and the mobile JSON envelope
(`redirect_or_json`) echoing the raw URL back to the caller. `target` is
computed before the write specifically so it stays in scope for the
`RecordNotUnique` rescue below; `bill_path` always yields a `String`, so
`target` is never nil.

## The regression this guards against

An older version of the finality check only asserted that the row count
stayed the same after a different-support re-POST — but the controller
used to quietly FLIP the stored support in that case, because
`find_or_initialize_by` plus `save` edited the row in place with no score
adjustment. A steady row count let that bug through undetected: the row
count really did stay the same, while the vote itself silently changed.
The current examples check the stored `support` value directly, not just
the count.

## Why a cast vote can never be changed

An existing vote skips the write path entirely: re-sending the same
`support` reports success without writing anything, and a different
`support` is rejected with no score adjustment. `#already_voted_response`
handles this uniformly: a re-POST with the SAME support reports success
(no new row, no score churn); a DIFFERENT support is rejected without
touching the stored vote or any derived total. It reuses the existing
dual web/mobile response envelope rather than inventing a new shape.

## Why `#create` rescues `RecordNotUnique`

A double-click race: the finality guard's `find_by` saw no row, but the
`(user_id, bill_id)` unique index rejected the concurrent INSERT. The row
exists now, so the rescue re-reads the winner and applies the same
finality rule instead of letting a 500 escape. If the row is somehow
absent (impossible while the unique index holds), it re-raises rather
than inventing a response.

## Browser coverage for a stale panel refused by the server

`spec/system/vote_panel_failure_spec.rb` proves end to end that when the
server refuses a vote because a vote is already final, the page does not
stay stuck on the vote it drew ahead of time. The story: a user opens a
bill they have not voted on, so the vote panel is live. On another device
the same user records an AGAINST vote for that bill. This page is now out
of date — its buttons still work — so it posts FOR. `#create` refuses it:
the stored vote stays AGAINST, no second row is written, and the web
response redirects back with an alert and errors, which runs the form's
error handler. That handler resets the panel to the vote the server
really holds, so the rejected FOR does not linger. The setup copies
`spec/system/user_voting_spec.rb`: passkey login with a fake
authenticator.

The example checks what is on the page before checking the URL: after the
redirect and reload, the panel shows the vote that is really stored — the
AGAINST from the other device — and never the rejected FOR. Waiting for
that settled state also waits out the POST; without the reset in the
error handler, the hopeful "FOR" banner would sit there. In the database,
either the finality check or the `RecordNotUnique` rescue above guarantees
exactly one row stays AGAINST, however the two threads interleave.

## Frontend: `useCastVote.ts`

Everything involved in casting a vote on a bill is pulled out of
`VotePanel` into this hook, so each theme's vote control — the ballot
oval, the poster block — offers the same action without rebuilding the
confirmation, the offline handling, the vote shown straight away and
undone on failure, the cache clearing, or the notification. Casting a
vote is the product's central action, so it gets exactly one
implementation.

Inertia's `useForm` copies its data into an internal ref from an effect,
after the render is committed. So calling `setData` and then `post()` in
one go would send the old value. `transform()` writes into a ref that is
read as the request is built, so the right `support` value ends up in the
body whatever the render timing.

On `onError`, the vote is put back to what the server says, so both
buttons come alive again and the person can try once more. That is
`undefined` when there was no earlier vote — for instance when the server
refuses because the vote is already final and this page is out of date.
This is a reset inside an event handler, not syncing with an outside
system, so no `useEffect`.

### Testing the rollback: `VotePanel.test.tsx`'s `useForm` mock

The real Inertia `useForm` keeps `data` in state and re-renders when
`setData` writes to it. An older test stand-in handed back a fixed empty
object, so it could never see the `support` value being written and then
undone, and could not witness the rollback on error. The current mock
merges `setData("support", value)` into state, so `data.support` — and
with it `VotePanel`'s idea of what was voted and what is disabled —
follows the component's own writes. It is written as `function useForm`
so the rules-of-hooks linter accepts the `React.useState` call inside it.
