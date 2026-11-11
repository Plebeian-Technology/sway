---
mode: explanation
summary: "Explains three non-obvious specifics of Sway's CSP: why both Sentry connect-src wildcards are needed, how the Vite dev server's script-src source works with the request nonce, and why the local error collector origin is added to connect_src."
status: agent-extracted
related: []
---

# Content Security Policy directive notes

Two specifics in `config/initializers/content_security_policy.rb` that look
redundant or unexplained at a glance, but aren't.

## Why both Sentry wildcard forms are needed

`connect_src` lists both `https://*.ingest.sentry.io` and
`https://*.ingest.us.sentry.io`. Both are needed, and the second is the one
that actually gets used.

Sentry sends events to a host built from the account's region. Sway's is
`o<org-id>.ingest.us.sentry.io`, which ends in
`.ingest.us.sentry.io`. The first wildcard, `*.ingest.sentry.io`, does not
match that host: a CSP wildcard only covers one label, and `us` sits as its
own label in between `ingest` and `sentry.io`. The second, more specific
wildcard is required to actually cover the real hostname.

In report-only mode (`content_security_policy_report_only`) the browser logs
the CSP violation while still letting the request through. Enforcing the
policy with only the first wildcard in place silently blocks every browser
error report from reaching Sentry, with no visible failure.

## How the Vite dev server CSP source works

In development, `script_src`, `style_src`, and `connect_src` all extend
themselves with `RailsVite.dev_server_csp_source`. That method returns a
lambda, not a string: the dev server's address is read per request from
`tmp/rails-vite.json`. That file only exists while the Vite dev server is
running, and the lambda contributes nothing to the policy when the file is
missing — so stopping the dev server tightens the policy automatically
instead of leaving a dead host allowed in it. The `websocket: true` form of
the same call rewrites the address for the HMR socket (`https` becomes
`wss`).

No `sha256` hash is pinned for the React Refresh preamble script.
`rails_vite` writes that inline script itself and gives it the request's
CSP nonce, so the nonce already covers it. An older approach pinned a hash
of the exact bytes `vite_ruby` emitted for that script, but that hash goes
stale the moment the emitted bytes change and was removed in favor of the
nonce.

## Why the local error collector origin is added to connect_src

The local error collector has to be named in `connect_src` too, or the
browser refuses to send the report. Without it, enforcing the policy
(`CSP_ENFORCE` set) silently stops every browser error report from arriving,
with no sign anything has changed.

The origin is read from the address the BROWSER uses
(`SwayLocalErrorDsn.browser_origin`), and only when it resolves to this
machine — `browser_origin` answers `nil` otherwise, so a pasted-in address
cannot widen the policy. It is added in every environment except
production, which has no local collector.

## Why enforcement is switched by CSP_ENFORCE

The policy is report-only unless `CSP_ENFORCE` is set to a non-empty value:
leaving it empty or unset reports violations without blocking anything. The
production deploy file in `config/deploy.yml` sets `CSP_ENFORCE: "true"`, so
production enforces the policy. Undoing enforcement means clearing that
variable and redeploying, with no code change.
