---
lat:
  mode: explanation
---

# Why some render_error calls add .to_s to non-nil fields

`render_error` demands non-nil `code:`/`message:` values.

Some callers — for example `OrganizationBillPositionsController#create`'s failure branch — hold a `Result` object whose `error`/`message` fields are typed nilable because they're only ever nil on the success and empty result variants, never in the branch actually calling `render_error`. Steep cannot see that branch invariant, so the call adds a bare `.to_s` to satisfy the non-nil signature rather than the type checker flagging a false positive.

## Why some call sites delegate to JsonErrorRenderable instead of hand-building the envelope

`Users::PreferencesController#render_preference_errors_from_message` delegates to the `JsonErrorRenderable` concern's `render_error` rather than building the `{ error: { code, message, ...

} }` hash by hand; the output is byte-identical either way, so delegating avoids a second place that could drift from the concern's shape.

## Why the envelope shape is pinned at the request-spec level, not per-controller

Every JSON error the app returns has the same shape: `{ error: { code, message, details?

} }`. `render_error` is the one place that builds it, and the mobile client (`mobile/src/api/client.ts`) reads that `code` to decide what to do. `spec/requests/json_error_envelope_spec.rb` pins this SHAPE on two representative endpoints rather than duplicating the assertion in every controller's own spec, so a slip back to a flat `{ error: "string" }` or a `{ success: false }` body is caught in one place.

## Why JsonErrorRenderable doesn't scrub details itself

`JsonErrorRenderable` is included into `ApplicationController`, so every controller has it, including the bearer-token API under `Api::V1`.

The browser paths are untouched by it — web errors still use a flash message and a redirect; only JSON-responding callers hit `render_error`. `details` is an optional hash carrying per-field validation errors, and the concern does no additional scrubbing of it: anything secret in the request parameters is already hidden from the logs by `filter_parameter_logging`, so there's no separate redaction step to duplicate here.
