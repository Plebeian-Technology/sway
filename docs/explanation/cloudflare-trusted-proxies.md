---
mode: explanation
summary: "Why production doesn't declare a manual trusted_proxies list — the cloudflare-rails gem and Rails' own defaults already cover the path a request takes."
status: agent-extracted
related: []
---

<!-- vale Vale.Spelling = NO -->

# Why `trusted_proxies` has no manual list

`trusted_proxies` is handled by the `cloudflare-rails` gem, not a manual
list. It patches `ActionDispatch::RemoteIp` / `Rack::Request` to trust
Cloudflare's edge ranges (fetched live, 12h cache, offline fallback), so
`request.remote_ip` resolves through the CF tunnel and self-updates when
Cloudflare rotates ranges. Rails' built-in loopback + RFC1918
`TRUSTED_PROXIES` already covers the kamal-proxy -> app hop.
`deploy.yml`'s `forward_headers: true` passes the CF headers through for the
gem to read.

## Why `spec/requests/force_ssl_spec.rb` checks config files and deleted methods, not live HTTPS behavior

Rails reads `force_ssl` and `ssl_options` once at boot into
`Rails.application.config`. Changing them partway through a test run would
mean rebooting the app, which RSpec cannot do cheaply. Deciding whether a
request arrived over HTTPS also depends on the whole Rack middleware stack
(`ActionDispatch::RemoteIp` and `ActionDispatch::SSL`): a bare
`ActionDispatch::Request.new(env)` does not apply the trusted-proxy
filtering `ssl?` relies on.

So this spec checks three other things instead: what the config files
say, that a method really was deleted at runtime, and — outside this
suite entirely — a human dry-run against a preview deploy for the real
network behavior.

The `cloudflare-rails` gem itself is checked only for being declared in
the production group of the Gemfile, for the same reason: the gem loads
only in production, where the app really does sit behind the Cloudflare
tunnel, and whether `remote_ip` actually resolves correctly through it is
one of the things that dry-run against a preview deploy checks, not
something a request spec can exercise.
