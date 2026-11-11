---
lat:
  mode: explanation
---

# Why Api::V1::BaseController replaces ApplicationController's auth gates

`ApplicationController` has two `before_action` gates that would both fire on `/api/*` requests reaching `/api/v1`:

1. `is_api_request_and_is_route_api_accessible?` — answers any `/api/*`
   request carrying no usable API key with a 401, which would pre-empt
   `/api/v1`'s per-action `public_endpoint?` hook.
2. `authenticate_sway_user!` — redirects HTML callers back (falling back to
   `root_url`) with a sign-in flash notice, which is wrong for JSON callers;
   they should get the standard error envelope instead.

`Api::V1::BaseController` skips both (`skip_before_action ...`) and replaces them with the JSON-emitting `authenticate_mobile_user!` gate, which respects `public_endpoint?`.

## Why the mobile-auth helpers live here

`credential_for_verify` and `build_bearer_token_payload` moved up into `Api::V1::BaseController` from `Api::V1::SessionsController` and `Api::V1::RegistrationsController`, where they used to exist as byte-identical copies.

Both children now call them via inheritance instead of maintaining two copies that could drift apart.
