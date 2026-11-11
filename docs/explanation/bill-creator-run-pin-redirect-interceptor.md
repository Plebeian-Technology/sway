---
mode: explanation
summary: "Why BillCreatorRunPinRedirects carries the pinned pipeline run across server-side redirects as a single _compute_redirect_to_location interceptor, reading the pin from the referer rather than the request"
status: agent-extracted
related: [docs/explanation/carried-run-pin-single-param-design.md, docs/explanation/pipeline-run-pin-vs-active-run.md, docs/explanation/current-address-without-owned-params.md]
---

# `BillCreatorRunPinRedirects`: carrying the run pin across server redirects

`withCarriedRunPin.ts` (see
[Why `withCarriedRunPin` carries one parameter, not the whole query](carried-run-pin-single-param-design.md))
solves this same problem on the browser side, for client-built addresses.
`BillCreatorRunPinRedirects` is the server-side equivalent, for redirects a
Rails controller issues.

## What the pin is

Choosing an older run from the dropdown puts `?run_id=` in the address.
Every Bill Creator screen reads it back out
(`LegislationPipelineRunSourcing#explicitly_selected_pipeline_run`); with no
`?run_id=` the screen shows the newest run instead. So dropping the
parameter does not lose a highlight — it silently swaps which run's stages,
errors, and bills the operator is reading, under an unchanged heading.

## Why this is one interceptor and not a change at each redirect

Many redirects across many controllers land on a Bill Creator page, and none
carried the pin before this concern — the browser side already solved the
equivalent problem for tab changes (`withCarriedRunPin.ts`), but the server
side never got the same treatment. Adding the parameter at each call site
leaves the next one to whoever writes it, and nothing fails when they
forget; one place every redirect already passes through cannot be
forgotten.

`_compute_redirect_to_location` is the one place: Rails funnels every
redirect through it — plain `redirect_to`, `redirect_back_or_to`, and every
option shape (a path helper's string, a record, a hash) — and hands back
the final address. Working on the computed address rather than on the
argument means the shape a caller passed does not matter here, and no
future redirect helper can slip past.

## Where the pin is read from, and why it is not the request

A write does not carry it: the browser sends `PATCH /bills/:id`, an address
the pin was never part of. The address it came FROM does hold it, so that
is what is read — the same move `OrganizationFollowsController` makes to
send a follow back to the page it was made on, `url_from` and all
(`url_from` returns nil for a referer pointing at another site, so a
foreign page cannot choose what goes into our redirect).

Only digits are accepted from the referer's `run_id`: the value is a
`LegislationPipelineRun` id and goes straight back into a redirect address,
so anything else is refused rather than escaped.

## Why it refuses to cross bills

Nothing scopes a run to a bill when the parameter is read, so carrying a
pin onto a different bill's page would show one bill's run under another
bill's heading. The browser side already avoids this by dropping the pin on
a bill switch; this matches that by carrying the pin only when the page
being left and the page being entered are the same bill. Two pages are the
same bill when both name the same id — the picker, which names no bill, is
never the same bill as anything, so a pin is not carried onto it or off it.

## Why the request specs drive every redirect through generate_summary

`spec/requests/bill_creator_run_pin_redirects_spec.rb` drives its
assertions through `BillsController#generate_summary` specifically:
every one of that action's branches redirects to the same Bill Creator
page, so the assertions can be about the redirect itself and not about
which branch ran. Before this concern existed, about fifty server
redirects landed on a Bill Creator page and not one carried the
`?run_id=` parameter, so saving anything returned the operator to the
newest run with nothing on screen saying so.

## Why a refusal's error messages are pinned alongside the run pin

Several Bill Creator redirects carry validation errors beside the path.
The errors travel in the session and the pin is written into the
address, so the two paths through the redirect do not meet today — but a
later rewrite of `_compute_redirect_to_location` could make them meet,
and a form that silently loses its error messages when it gains the pin
would fail with nothing on screen to explain it. A regression spec pins
both together so that a future rewrite that breaks the interaction fails
loudly instead.

## A malformed query never breaks a redirect

A malformed query is treated as no query rather than raising: this sits on
every redirect in the application, so it must never be the reason one
fails.
