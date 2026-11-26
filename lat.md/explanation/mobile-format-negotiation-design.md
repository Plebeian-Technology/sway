---
lat:
  mode: explanation
---

# MobileFormatNegotiation design notes

`MobileFormatNegotiation` lets one controller action serve two clients: the website (cookie session, Inertia pages) and the mobile app (bearer token, plain JSON).

The JSON body is exactly the same hash the Inertia page would receive as props; an Inertia redirect becomes a `{ redirect, flash }` JSON object.

## Why render_inertia_or_json resolves prop wrappers itself

Inertia prop wrappers (`InertiaRails.defer`, `.always`, `.lazy`, `.merge`) are placeholder objects.

Inertia prop wrappers (`InertiaRails.defer`, `.always`, `.lazy`, `.merge`) are placeholder objects — Inertia unwraps them for the web automatically, but mobile JSON rendering has to call `.call(controller)` on them itself, or the response would serialize the placeholder object into nothing useful rather than the value it wraps.

## Why paste-summary's mobile JSON spec asserts content type, not just body shape

Asserting the response `content_type` is what keeps `spec/requests/bills_paste_summary_spec.rb`'s mobile JSON examples honest.

If `mobile_api_request?` ever got stricter — say it started demanding a bearer token — the request would quietly take the web Inertia branch instead. That branch also answers 200 on the happy path, so a bare `body["bill"]` check alone could still pass by accident, with the example no longer proving what it claims to prove.

## Why redirect_or_json compacts the flash key

`redirect_or_json` translates an Inertia redirect into a `{ redirect, flash }` JSON envelope for mobile.

`flash_message` is compacted out when `nil`, so the wire format is `{ redirect: "/path" }`, never `{ flash: null }` — keeping the shape minimal for clients that treat a present key as meaningful.

## Why respond_after_write answers a failed write with 422

`respond_after_write` replaces the hand-written split between a redirect for the website and JSON for the mobile app on admin writes, and it gives a failed write a status that `redirect_or_json` cannot.

`redirect_or_json` always answers 200 with a `{ redirect, flash }` body, so a mobile client cannot tell a rejected write from a saved one. When `errors` or `alert` is present, the helper instead calls `render_error` with status 422, code `validation_failed`, the alert (or "Validation failed.") as the message and `errors.to_hash` as details, so an `ActiveModel::Errors` object serializes without a caller conversion. The web branch passes `inertia: { errors: }` only when errors are present, so a plain redirect never writes an empty error hash into the session. `back` selects `redirect_back_or_to(path)` over `redirect_to(path)`, and `status` (for example `:see_other`) reaches either redirect unchanged.

## Why resolve_inertia_props doesn't honor defer/lazy semantics for mobile

`resolve_inertia_props` walks the props hash and replaces any `InertiaRails::BaseProp` (`Defer`, `Always`, `Lazy`, `Merge`) with the value its block produces inside the controller.

`resolve_inertia_props` walks the props hash and replaces any `InertiaRails::BaseProp` (`Defer`, `Always`, `Lazy`, `Merge`) with the value its block produces inside the controller; nested hashes are walked too, everything else passes through. Defer's grouping hint and lazy's "only when asked for" behavior are not honored for mobile — JSON callers always get the finished value in one response, since there is no follow-up partial-reload mechanism on the mobile side to defer to. Bare `Proc`s are called too, matching how the web side treats a lambda prop.

## Why the Proc branch needs steep:ignore

The type checker can't match a plain `Proc` against the block type `instance_exec` declares in its signature; the `when Proc` branch is the real contract, and at run time it evaluates an Inertia prop lambda inside the controller.

The `steep:ignore:start`/`:end` pair scopes the suppression to exactly that call.
