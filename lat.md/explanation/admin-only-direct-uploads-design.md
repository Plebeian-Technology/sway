---
lat:
  mode: explanation
---

# Why AdminOnlyDirectUploads exists

Active Storage brings its own controllers, and they descend from `ActionController::Base` rather than from Sway's `ApplicationController`, so none of Sway's `before_action`s ever run on them.

Its upload endpoint hands the caller a database row and a signed URL that writes into the assets bucket, and everything in that bucket can be read by anyone. Forgery protection is no help here: a caller can fetch any page to get a session and a CSRF token, which is all an unauthenticated uploader needs.

The gate is session-only, on purpose: API keys belong to outside readers, there is no mobile screen that uploads, and every upload screen the site has is an admin one.

## Why the request spec checks blob count, not just status

This controller belongs to Rails, not to Sway, so it is not covered by the "requires sway admin" shared example — that example asserts the refusal shape `ApplicationController` produces, and this controller never reaches it.

Every example checks the blob COUNT as well as the response status, because status alone would pass on a guard that refuses only after the row is already written — the outcome that does real damage.

## Why both the allow and refuse branches are logged

Both branches are logged because the endpoint otherwise records NOTHING: an unauthorised upload leaves no row, session, or log that could say who sent it.

The database keeps no requester for this endpoint, sessions live only in the visitor's cookie, and container logs die with the container — so this before_action's own logging is the only durable record of who used the upload endpoint and when.
