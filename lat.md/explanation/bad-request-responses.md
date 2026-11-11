---
lat:
  mode: explanation
---

# Bad request responses

A request whose body cannot be parsed is the sender's mistake, and Rack marks the errors it raises for that with `Rack::BadRequest`. Sway answered them with 500 until `BadRequestMiddleware` caught the family.

## Rack's own bad-request family answers 400

Every error class carrying the `Rack::BadRequest` marker is caught in one place rather than named one at a time.

The marker exists so an application does not have to track the list, which in
rack 3.2.7 runs to a multipart part limit, a total part limit, empty content, a
boundary that is too long or never arrives, a missing input, a parameter of the
wrong type, an invalid parameter and a query nested past its depth limit. Naming
them individually would leave the next one rack adds to page an operator, which
is how this one arrived.

The response is a plain-text `Bad Request` with no detail in it. A sender who
produced an unparsable body learns nothing useful from a longer message, and an
attacker probing limits learns which limit was hit.

## Why it sits above the method-override check

`Rack::MethodOverride` parses the body of every POST before routing, to see whether it carries a `_method` field, and it sits above the layer of Rails that turns bad requests into a polite response.

It rescues some of the family itself — invalid and mistyped parameters, a
too-deep query, and `EOFError` — but not the boundary errors, and one of those is
what a POST announcing a multipart body without its boundary raises after sixteen
kilobytes. That escaped past every Rails handler to the web server, which
answered 500 and reported a fault in Sway.

The report also blamed `ReportingEndpointsMiddleware`, because that was the
nearest Sway file on the way back out. It only passes requests along.

## A path nothing matches stays on this machine

The catch-all answers a mistyped path without sending the reader to another host, and it refuses to swallow the application's own prefixes.

Redirecting to the live site is right for the canonical-host rule and wrong as a
response to an unmatched path, because a machine that is not production would be
handing its readers to production — an earlier example asserted exactly that
redirect from the test environment, and the application was what changed. The
prefix guard is separate and has to survive the catch-all being switched on:
`/rails`, `/api`, `/vite` and `/assets` belong to something, so a request under
one of them failing visibly is more useful than a redirect that hides it.

The catch-all route is drawn only when `config.x.catch_all_enabled` is set for production. Development and test leave it absent, so an unmatched path gets an immediate 404 instead of being redirected to the production host; the excluded Rails, API, Vite, and asset prefixes remain outside the rule. [[config/routes.rb]] owns the route boundary and [[config/environments/production.rb]] enables the setting.

## What the middleware stops reporting

A genuinely broken upload from inside the application now fails as a quiet 400 rather than as an error somebody is paged about.

That is the trade this makes, and the reason each rejection is logged with the
request path and the error class through `SwayLogging` rather than being dropped:
a burst of them against one path is the shape a real upload defect would take,
and it stays visible in the logs. Sentry is deliberately not told, since the
whole point is that a malformed body from the open internet is not a fault worth
waking anybody for.

## JavaScript format probes answer 406

[[app/controllers/application_controller.rb#ApplicationController#reject_js_request_format]] and [[app/controllers/embed/base_controller.rb#BaseController#reject_js_request_format|Embed::BaseController#reject_js_request_format]] refuse `request.format.js?` with `406 Not Acceptable` before action dispatch.

Sway serves no `.js.erb` templates or UJS responses, so `Accept: text/javascript` and `?format=js` requests come only from scanners probing for legacy Rails endpoints. Because Action View's `html_fallback_for_js` flag keeps `lookup_context.formats.first` as `:js` even when `InertiaRails::Renderer` passes `formats: :html`, letting a `.js` request reach `render inertia:` causes `ActionView::Layouts#_default_layout` to search for a `.js` layout and raise an unhandled `ArgumentError`. Halting with `head :not_acceptable` in a `before_action` returns 406 without overriding Rails rendering internals or paging Sentry.
