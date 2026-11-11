---
mode: explanation
summary: "Why SwayLogging redacts Anthropic API keys separately from Rails' parameter filter, and a nested-hash redaction bug it fixed."
status: agent-extracted
related: []
---

<!-- vale Vale.Spelling = NO -->

# SwayLogging design notes

## Why `.redact_anthropic_key` exists separately from Rails' filter

Rails' parameter filtering (`ActiveSupport::ParameterFilter`) only looks at
parameter NAMES — the pattern in
`config/initializers/filter_parameter_logging.rb` matches keys, never
values. Sway needs its own helper for the case where the caller is about to
log a whole string, such as a response body or payload that might contain a
leaked Claude API key (they look like `sk-ant-XXX`).

Run raw response bodies and third-party SDK debug dumps through
`.redact_anthropic_key` before handing them to `Rails.logger` or
`SwayLogging.info`/`.warn`/`.error`. `spec/config/filter_parameters_spec.rb`
shows both the key-only behavior of the Rails filter and how to use this
helper.

## Why `filter_parameters` lists `:anthropic_api_key` alongside the `:_key` substring matcher

`config/initializers/filter_parameter_logging.rb`'s `:_key` Symbol already
matches `anthropic_api_key` as a substring, under
`ActiveSupport::ParameterFilter`'s partial-match rule. The separate
`:anthropic_api_key` entry is mostly documentation: it states the intent
explicitly and adds a second, redundant layer, so a future edit that
removes the generic `:_key` matcher (for being too broad, say) does not
silently stop scrubbing the Claude API key too. The `sk-ant-` `Regexp`
alongside both is the entry doing genuinely new work: it catches raw key
VALUES that travel through places never tied to a key literally named
`anthropic_api_key`, such as a body or header dump — the gap the next
section covers.

## What `.log_exception` protects against

`.log_exception` strips any `sk-ant-` key out of BOTH the `error_message`
field AND the full backtrace dump before either reaches `Rails.logger`.
Without this, an exception whose message or backtrace quotes a leaked
`ANTHROPIC_API_KEY` — say Faraday wrapping a 401 and echoing the auth header
back — would write the real key into the log, because
`Rails.application.config.filter_parameters` only matches key names, not
values.

`.redact_anthropic_key` was written before anything called it, which left
open the exact exposure it exists to close: nothing invoked it, so a leaked
key in an exception message or backtrace still reached the log unredacted.
It is now wired into `.log_exception`, the likeliest place a
key escapes, since Faraday wrapping a 401 alongside the auth header is a
realistic way for a raw key to land in an exception's own text.

## Why the `:anthropic_api_key` spec checks the joined filter list, not its shape

After the first request runs, `ActiveSupport::ParameterFilter` may fold the
whole `filter_parameters` list into one combined `Regexp` internally, so a
spec that expects to find a standalone `:anthropic_api_key` Symbol in the
list can start failing for a reason that has nothing to do with a
regression. `spec/config/filter_parameters_spec.rb` checks the RESULT
instead of the shape: it joins every matcher's `#inspect` output into one
string and asserts the `anthropic_api_key` marker appears somewhere in it,
whether that is still its own Symbol entry or has been baked into the
combined Regexp. The joining helper is written inline as a `let` rather
than a named method, so Steep needs no signature for what is a one-off
test helper.

## Why `invited_by_id` logs presence, not the value

`ApplicationController#invited_by_id` logs
`SwayLogging.info("invited_by_id.lookup", invited: value.present?)` rather
than the cookie value itself. The cookie value identifies the inviter —
personal data — but the `UserInviteLink::INVITED_BY_SESSION_KEY` key it is
stored under is not in `SENSITIVE_KEYS`, so `SwayLogging`'s key-name-based
redaction would not catch it and the value would be inlined into the log
verbatim. Logging only whether it is present avoids that.

## Why `.summarize`'s Hash branch redacts at every nesting level

`.sanitize_value` only checks the top-level key. An earlier version of the
Hash branch in `.summarize` shortened values without looking at inner
keys — so a sensitive key one level down, such as `SmsDeliveryJob`'s
`{to:, body:}` job arguments, went into the log unscrubbed. `.summarize` now
checks every key against `SENSITIVE_KEYS` on the way down.
