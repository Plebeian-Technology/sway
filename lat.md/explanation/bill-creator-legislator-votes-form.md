---
lat:
  mode: explanation
---

# BillCreatorLegislatorVotes mechanics

Why BillCreatorLegislatorVotes keeps its own useForm() instead of sharing SwayFormContext, how it batches vote-support state for ~535-legislator locales, and why its onError handler is required.

## Why it keeps its own useForm() instead of sharing SwayFormContext

Sends exactly what the old creator sent:

```
POST /legislator_votes
{ bill_id, legislator_votes: [{ legislator_id, support }, ...] }
```

Keeps its own useForm() instead of sharing SwayFormContext — votes have always been submitted separately: saving from /bills doesn't include them, and /legislator_votes is its own admin controller action.

## Why REFUSAL_FALLBACK only applies when the server sent no message

Used only when the server sent no message of its own. The server's message names the legislator ids that failed, so it always wins when there is one.

## Why there is no ?saved= check for the create/update toast

"Bill Created" and "Bill Updated" arrive from Rails as a flash message (shared through inertia_share), and registerFlashToasts shows each one once. There is no ?saved= check here.

## Why legislator_votes_refreshed_at gets its own notify()

Tells the admin when votes were refreshed behind their back — BillsController#edit sends these props when LegislatorVote rows were pulled in automatically since the last visit.

Shown exactly once per page load via the existing notify() helper — do NOT bring in notistack.

## Why supportByLegislator is built as a single-pass lookup map

Builds a lookup table in one pass so each row costs one lookup — searching all three lists per legislator would cost legislators × votes, which hurts at ~535 members (US Congress).

## Why onSelectSupport uses the setData(prev => ...) form

A legislator holds only one position — recording a vote drops them from all three lists, then adds them back to the chosen one.

Uses the setData(prev => ...) form instead of reading `data` from scope, so \[setData] is the only dependency and this keeps a stable identity between renders.

That matters because the memo-wrapped vote rows — ~535 of them in the US Congress locale — would otherwise all redraw on every click.

## Why the submit handler needs an explicit onError

When LegislatorVotesController#create refuses, it sends `inertia: {errors: {legislator_votes: message}}` and no flash\[:alert].

Without this handler the redirect lands silently, onFinish re-enables the button, and nothing tells the operator it failed.

This screen edits the public vote record — a silent failure leaves it wrong while the admin believes it's fixed.
