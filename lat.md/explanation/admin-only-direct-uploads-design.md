---
lat:
  mode: explanation
---

# Why AdminOnlyDirectUploads exists

Active Storage brings its own controllers, and they descend from `ActionController::Base` rather than from Sway's `ApplicationController`, so none of Sway's `before_action`s ever run on them.

Its upload endpoint hands the caller a database row and a signed URL that writes into the assets bucket, and everything in that bucket can be read by anyone. Forgery protection is no help here: a caller can fetch any page to get a session and a CSRF token, which is all an unauthenticated uploader needs.

The gate admits a Sway admin in one of two ways: a signed-in browser session, or a bearer token from the mobile app. Every upload screen on either client is an admin one, so both paths ask the same question.

## Why a bearer token decides identity on its own

A request that carries an `Authorization` header is judged on its token alone; the session cookie is never read.

A fallback to the cookie would let a junk or non-admin token ride an admin's browser session. [[identity-and-access#Sessions, cookies and bearer tokens]] sets the same rule for `ApplicationController`.

The token counts only when [[app/models/api_key.rb#ApiKey]] resolves it to an active key whose bearer is a `User` who is a Sway admin. An API key's bearer is polymorphic, so a key held by any other kind of record is refused.

Forgery protection is skipped only for such an admin token. A browser never attaches a bearer token on its own, and a cross-site page cannot read one, so the token itself proves the request came from its holder. Any other request, a non-admin token included, still needs a CSRF token; a cookie request with no `Authorization` header behaves exactly as before.

This controller inherits `ActionController::Base`, not `ApplicationController`, so the concern brings in [[app/controllers/concerns/api_key_authenticatable.rb#ApiKeyAuthenticatable]] and declares the forgery skip itself.

## Why the request spec checks blob count, not just status

This controller belongs to Rails, not to Sway, so it is not covered by the "requires sway admin" shared example — that example asserts the refusal shape `ApplicationController` produces, and this controller never reaches it.

Every example checks the blob COUNT as well as the response status, because status alone would pass on a guard that refuses only after the row is already written — the outcome that does real damage.

## Why both the allow and refuse branches are logged

Both branches are logged because the endpoint otherwise records NOTHING: an unauthorised upload leaves no row, session, or log that could say who sent it.

The database keeps no requester for this endpoint, sessions live only in the visitor's cookie, and container logs die with the container — so this before_action's own logging is the only durable record of who used the upload endpoint and when.
