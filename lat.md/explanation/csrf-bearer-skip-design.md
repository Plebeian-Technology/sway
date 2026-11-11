---
lat:
  mode: explanation
---

# Why CSRF is skipped per-request, not per-controller (H1 fix)

CSRF protection stops another site from making requests on a signed-in user's behalf.

A mobile client authenticates with a bearer token instead of a session cookie, and a bearer token already proves the request came from the client holding it — a forged cross-site form cannot attach one, so CSRF protection has nothing to add for that request.

Sway switches the check off one request at a time with `skip_forgery_protection if: :bearer_authorization_header?`, rather than disabling `ApplicationController.allow_forgery_protection` for a whole controller or the app. The conditional keeps the two call shapes fully separate: the same endpoint enforces CSRF for a cookie-authenticated browser request and skips it for a bearer-authenticated one, decided fresh on every request from whether that request actually carries a bearer header — never from what kind of request the endpoint usually serves.

`bearer_authorization_header?`'s check is deliberately narrower than the app's general `mobile_api_request?` predicate: a cookie request that also sends `Accept: application/json` (matching `mobile_api_request?`) but no Bearer header still needs a CSRF token, because the credential doing the authenticating is still the cookie.

`spec/requests/csrf_enforcement_regression_spec.rb` pins this behavior down.

## A second layer for /api/v1

`Api::V1::BaseController` additionally sets `protect_from_forgery with: :null_session` for the whole `/api/v1` namespace.

Instead of raising on a missing CSRF token, Rails treats the request as having an empty session. This is a second layer of safety alongside `ApplicationController`'s `skip_forgery_protection if: :bearer_authorization_header?` — evaluated per request, so it introduces no class-level state changes either.
