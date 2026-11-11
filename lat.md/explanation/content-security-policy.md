---
lat:
  mode: explanation
---

# Content Security Policy

Sway sends a browser policy with every page, built in one initializer. Whether that policy blocks anything or only reports it is a deploy-time switch, set to enforce in production and left reporting everywhere else.

## The CSP_ENFORCE staging switch

`config/initializers/content_security_policy.rb` derives `content_security_policy_report_only` from `ENV["CSP_ENFORCE"]` at boot. An unset or empty variable leaves report-only on; any value enforces.

Production sets that variable to `"true"` in `config/deploy.yml` under `env:
clear:`, so from the first deploy carrying that
line a browser receives `Content-Security-Policy` rather than
`Content-Security-Policy-Report-Only`. Report-only stays the default wherever
the variable is absent: development, test, and a laptop preview of the
production build. Rollback is the removal of that one line and a redeploy,
with no code change.

The variable is read once, while the initializer runs, so nothing inside a
live process can move between the two modes. The header name moves with them —
`Content-Security-Policy-Report-Only` while reporting,
`Content-Security-Policy` while enforcing — which is why
`spec/requests/content_security_policy_spec.rb` and
`spec/requests/csp_reports_spec.rb` read whichever of the two carries the
policy instead of naming one, and why both modes are covered by running those
files twice rather than by stubbing the variable inside an example.

The directive set itself does not branch on the switch. `report-uri
/csp-report` is emitted in both modes, so the violation reports that justify
the flip keep arriving after it.

One directive does change behaviour with the switch rather than with its own
configuration. `upgrade-insecure-requests` is added for production only, and it
has no effect in a report-only policy — Chromium-based browsers log that on
every page load, four times over. Enforcement is the point at which it first
acts, on mixed content inside page markup. Scheme upgrading itself is covered
twice already: Cloudflare answers an http request with a redirect to https,
and Rails sends HSTS for a year.

## What the local enforcement audit found

Enforcement changes no outcome in the test environment. The two
CSP request specs and the whole browser suite give the same results whether
`CSP_ENFORCE` is unset or `CSP_ENFORCE=1`.

The browser suite is the part that carries weight here. A request spec only
reads a header, while Chrome applies the policy and refuses what it forbids, so
a blocked script or stylesheet arrives as a missing control rather than as a
log line. No directive was widened for the enforced runs, which leaves the
production page set, rather than the policy's shape against the pages specs
exercise, as the remaining unknown before the flip.

## External API connect-src origins

Address autocomplete endpoints and third-party geocoding origins are permitted in `connect-src` to support direct lookups and rapid provider rollbacks.

Nominatim (`https://nominatim.openstreetmap.org`) is permitted under `connect-src` alongside internal endpoints (`/addresses/autocomplete`) so client requests or fallbacks succeed without triggering policy violations. Legacy Google Maps endpoints (`https://maps.googleapis.com` and `https://*.googleapis.com`) remain permitted in `connect-src` so an instant rollback to Google Places autocomplete requires no policy adjustment, while `script-src` in [[config/initializers/content_security_policy.rb]] pins exact script origins (`https://maps.googleapis.com`, `https://challenges.cloudflare.com`, and `https://static.cloudflareinsights.com`) rather than `*.googleapis.com` or `*.cloudflare.com` wildcards so storage buckets (`https://storage.googleapis.com`) and JSONP endpoints cannot satisfy `script-src`.

## Why CORS is not configured

Sway does not mount `Rack::Cors` because every client talks to the Rails origin directly without cross-origin browser requests.

Web pages render through Inertia on the same origin as the Rails app (`app.sway.vote` in production and `localhost:3333` in development), and the React Native mobile app makes native HTTP calls that do not enforce browser CORS headers ([[config/application.rb]]). Leaving `Rack::Cors` unmounted keeps the default same-origin browser boundary intact.
