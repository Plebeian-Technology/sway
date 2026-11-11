---
mode: explanation
summary: "Explains why the ActionCable WebSocket URL needs its own log-scrubbing pass, separate from Rails' request-parameter filtering."
status: agent-extracted
related: []
---

<!-- vale Vale.Spelling = NO -->

# Why the WebSocket URL gets its own log scrubbing

Rails' `filter_parameters` (configured in
`config/initializers/filter_parameter_logging.rb`) only cleans values sent
as request parameters. It does not touch values sitting in the URL itself.

The mobile app's WebSocket client (`mobile/src/channels/consumer.ts`) opens
`wss://app.sway.vote/cable?token=<login token>`, because the ActionCable
JavaScript library has no supported way to send a custom header instead.
Without extra cleanup, that login token would appear in full in any log line
that mentions the WebSocket URL — ActionCable's own connection log, or
web-server access logs written through the Rails logger.

`ActionCableTokenScrubbing` wraps the logger's formatter and rewrites
`/cable?...token=<value>` to `/cable?...token=[FILTERED]` in every line that
passes through it. The pattern requires `/cable?` before `token=`, so it
leaves alone unrelated `token=` values on other URLs — those are already
covered by `filter_parameters` when they arrive as request parameters.

## Why `consumer.ts` puts the token on the query string instead of a header

An `Authorization` header would be the better way, because the token would
then never appear in URLs, proxy logs, or Rails request lines.
`@rails/actioncable` v8 offers no public `headers` option on
`createConsumer`, and even with a WebSocket subclass, React Native's
WebSocket client usually refuses custom headers during the opening
handshake. So the mobile client puts the token in the query string instead
and leans on the Rails log scrubber described above to mask
`/cable?token=<value>` anywhere it is logged.

Whichever approach is live is recorded in the `consumer.ts` module and
readable through `currentAuthStrategy()`, so a later move to header auth
can be observed without touching any call site.

Without a token, the consumer connects with no credentials and Rails turns
the subscription away in `ApplicationCable::Connection#find_verified_user`.

## `consumer.ts`'s single shared consumer

`getConsumer(token)` hands back one shared consumer. The FIRST caller's
token is the one used for the rest of the session; later callers get that
same consumer whatever token they pass, which matches
`@rails/actioncable`'s assumption of a single WebSocket.

`destroyConsumer()` is called from `useSession.signOut`, so the next
sign-in builds a fresh consumer with the new token. It also clears the
recorded auth-strategy approach, so `currentAuthStrategy()` reflects the
signed-out state.

`react-native-url-polyfill/auto` must be imported once when the app starts
(it already is, in `index.js`), so URL parsing inside `@rails/actioncable`
works in the React Native runtime.

## Why the Claude API key gets a second, pattern-based filter

`config/initializers/filter_parameter_logging.rb` also adds a second layer
of protection against accidentally logging the Claude API key. The
`:anthropic_api_key` entry in the `filter_parameters` list is there to state
the intent — the `:_key` entry already covers it, since these names match on
any part of the parameter name. The regex layer
(`/sk-ant-[A-Za-z0-9_-]+/`) adds something new: it blanks out anything
starting with `sk-ant-` (how every Anthropic key starts) wherever it shows up
in a logged body or header, even when it did not arrive in a parameter named
`anthropic_api_key` — say an echoed response body or a debug dump from a
library. The character set matches the letters, digits, `_` and `-` that
Anthropic keys are documented to use.
