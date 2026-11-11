---
mode: explanation
summary: "Why ApplicationCable::Connection's encrypted refresh_token cookie fallback runs the same RefreshToken#is_valid? check as HTTP auth, and how its spec stubs the cookie jar."
status: agent-extracted
related: []
---

# `ApplicationCable::Connection`'s refresh-token cookie fallback

With no session, `ApplicationCable::Connection#connect` falls back to an
encrypted `refresh_token` cookie. That fallback has to run the same check
HTTP auth runs — `RefreshToken#is_valid?(request)` — so an expired cookie,
or one replayed from a different IP address or browser, cannot open an
authenticated WebSocket.

## How the spec exercises the fallback

`rspec-rails`'s `connect` helper gives no access to the encrypted cookie
jar, so each example in `spec/channels/connection_spec.rb` stubs the
connection's `cookies` to hand back the token. The fake request that
`connect` builds reports `remote_ip` `"0.0.0.0"` and `user_agent`
`"Rails Testing"`; `is_valid?` compares the token's stored `ip_address` and
`user_agent` against those two values.

The stub is repeated inside every example rather than pulled into a `def`
helper. The type checker (Steep) reads an example group body as a plain
object and cannot see RSpec helper methods, and other specs in this file
follow the same rule.
