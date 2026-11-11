---
mode: explanation
summary: "Why is_api_request_and_is_route_api_accessible? checks performed? after authenticate_with_api_key! instead of trusting its return value, and how the mobile-vs-web 403 shape stays consistent across admin gates."
status: agent-extracted
related: []
---

<!-- vale Vale.Spelling = NO -->

# Why the `/api/` admin gate checks `performed?`, not a return value

`ApplicationController#is_api_request_and_is_route_api_accessible?` calls
`authenticate_with_api_key!` and then returns early if `performed?` is
true, rather than trusting that method's own return value.

A missing or invalid API key already renders its own 401 (plain text) from
inside `authenticate_with_api_key!`. That render call's return value is
truthy, but it is not a signal that authentication succeeded — it is just
what `render` returns. Checking `current_user&.is_sway_admin?` against it
anyway used to raise `DoubleRenderError` on an admin route reached with no
token at all. Bailing the moment a response has already gone
out, via `performed?`, avoids trusting a return value that was never a
success signal in the first place.

Once past that check, reaching the `/api/admin/` refusal below means the
request DID carry a usable key — a missing or unrecognized one would have
already answered above. So the only refusal left to make is a request to
an `/api/admin/` route whose key belongs to someone who is not a Sway
admin, and the message says that, rather than asking for a key the caller
already supplied.

## Why a request with no `Authorization` header gets a plain-text 401, not the JSON message

`authenticate_with_api_key!` is built on Rails' own
`authenticate_or_request_with_http_token`. With no `Authorization` header
at all, that Rails method answers 401 on its own — plain text, not
JSON — before any of this controller's code runs; that behavior predates
and is unrelated to the `performed?` dedup above. The JSON message naming
admin rights, described above, is only ever reached by a request that DID
carry a valid token and failed the admin check specifically — which is
why that message names admin rights, and never a missing key.

## Mirroring the mobile-vs-web split in `verify_is_sway_admin`

`ApplicationController#verify_is_sway_admin` answers a non-admin the same
way `#authenticate_sway_user!` already does elsewhere in this class:
mobile/bearer clients get a JSON 403 with no `Location` header
(`mobile_api_request?`), while HTML/Inertia clients get the usual redirect
to the root path.
