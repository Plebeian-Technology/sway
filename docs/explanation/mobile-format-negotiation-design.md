---
mode: explanation
summary: "Design notes for the MobileFormatNegotiation concern: why it resolves Inertia prop wrappers by hand for mobile JSON, the redirect_or_json wire format, and the steep:ignore around instance_exec-ing a lambda prop."
status: agent-extracted
related: [docs/explanation/csrf-bearer-skip-design.md]
---

<!-- vale Vale.Spelling = NO -->

# `MobileFormatNegotiation` design notes

`MobileFormatNegotiation` lets one controller action serve two clients:
the website (cookie session, Inertia pages) and the mobile app (bearer
token, plain JSON). The JSON body is exactly the same hash the Inertia
page would receive as props; an Inertia redirect becomes a
`{ redirect, flash }` JSON object.

## Why `render_inertia_or_json` resolves prop wrappers itself

Inertia prop wrappers (`InertiaRails.defer`, `.always`, `.lazy`, `.merge`)
are placeholder objects — Inertia unwraps them for the web automatically,
but mobile JSON rendering has to call `.call(controller)` on them itself,
or the response would serialize the placeholder object into nothing
useful rather than the value it wraps.

## Why paste-summary's mobile JSON spec asserts content type, not just body shape

Asserting the response `content_type` is what keeps
`spec/requests/bills_paste_summary_spec.rb`'s mobile JSON examples honest.
If `mobile_api_request?` ever got stricter — say it started demanding a
bearer token — the request would quietly take the web Inertia branch
instead. That branch also answers 200 on the happy path, so a bare
`body["bill"]` check alone could still pass by accident, with the example
no longer proving what it claims to prove.

## Why `redirect_or_json` compacts the flash key

`redirect_or_json` translates an Inertia redirect into a
`{ redirect, flash }` JSON envelope for mobile. `flash_message` is
compacted out when `nil`, so the wire format is `{ redirect: "/path" }`,
never `{ flash: null }` — keeping the shape minimal for clients that treat
a present key as meaningful.

## Why `resolve_inertia_props` doesn't honor defer/lazy semantics for mobile

`resolve_inertia_props` walks the props hash and replaces any
`InertiaRails::BaseProp` (`Defer`, `Always`, `Lazy`, `Merge`) with the
value its block produces inside the controller; nested hashes are walked
too, everything else passes through. Defer's grouping hint and lazy's
"only when asked for" behavior are not honored for mobile — JSON callers
always get the finished value in one response, since there is no
follow-up partial-reload mechanism on the mobile side to defer to. Bare
`Proc`s are called too, matching how the web side treats a lambda prop.

## Why the `Proc` branch needs `steep:ignore`

The type checker can't match a plain `Proc` against the block type
`instance_exec` declares in its signature; the `when Proc` branch is the
real contract, and at run time it evaluates an Inertia prop lambda inside
the controller. The `steep:ignore:start`/`:end` pair scopes the
suppression to exactly that call.
