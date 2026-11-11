---
mode: explanation
summary: "Explains why Bill Creator actions need a shared helper to surface server refusals that arrive as errors props with no flash alert."
status: agent-extracted
related: [docs/reference/refusal-key-catalog.md]
---
<!-- vale Vale.Spelling = NO -->

# Why `notifyServerRefusal` exists

`BillsController` and `BillDraftOrgPositionsController` report every
refusal the same way: a redirect carrying `errors: { <key>: <message> }`,
with no flash alert at all.

`flashToasts.ts` reads only `flash.notice` / `flash.alert`, and no Bill
Creator component read `props.errors.org_position` or
`props.errors.generation` before this helper existed. So the refusal went
down a channel nobody listened on: the redirect arrived, the button
re-enabled, the card sat there, and it looked exactly like a slow request
rather than a refusal — with no indication to the operator that anything
had gone wrong.

## A pattern already solved once, pulled into one place

`CategoryRow.tsx` already solved the same problem for the admin categories
screen: without an error handler, the visit rejects and the row sits stuck
with no feedback. `notifyServerRefusal`
(`app/frontend/components/admin/creator/notifyServerRefusal.ts`) is that
pattern pulled into one place, so every Bill Creator action hitting these
endpoints shares a single implementation instead of copies that can drift
apart from each other.

See [the refusal-key catalog](../reference/refusal-key-catalog.md) for
which keys the controllers behind this screen actually send.

## Why serverRefusalMessage checks the shape carefully

It checks the shape carefully: `onError` receives `props.errors` exactly
as it arrived, and a controller elsewhere may nest errors
(`{category: {name: message}}`).

An all-blank string is no more use to show than a missing one.

## Why notifyServerRefusal prefers the server's wording, with a fallback

The server's wording wins because it is the only text that names the real
reason. The fallback is there so an unexpected failure still says
something rather than nothing.
