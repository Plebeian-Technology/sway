---
lat:
  mode: explanation
---

# Why trusted_proxies has no manual list

`trusted_proxies` is handled by the `cloudflare-rails` gem, not a manual list.

It patches `ActionDispatch::RemoteIp` / `Rack::Request` to trust Cloudflare's edge ranges (fetched live, 12h cache, offline fallback), so `request.remote_ip` resolves through the CF tunnel and self-updates when Cloudflare rotates ranges. Rails' built-in loopback + RFC1918 `TRUSTED_PROXIES` already covers the kamal-proxy -> app hop. `deploy.yml`'s `forward_headers: true` passes the CF headers through for the gem to read.

## Why spec/requests/force_ssl_spec.rb checks config files and deleted methods, not live HTTPS behavior

Rails reads `force_ssl` and `ssl_options` once at boot into `Rails.application.config`.

Changing them partway through a test run would mean rebooting the app, which RSpec cannot do cheaply. Deciding whether a request arrived over HTTPS also depends on the whole Rack middleware stack (`ActionDispatch::RemoteIp` and `ActionDispatch::SSL`): a bare `ActionDispatch::Request.new(env)` does not apply the trusted-proxy filtering `ssl?` relies on.

So this spec checks three other things instead: what the config files say, that a method really was deleted at runtime, and — outside this suite entirely — a human dry-run against a preview deploy for the real network behavior.

The `cloudflare-rails` gem itself is checked only for being declared in the production group of the Gemfile, for the same reason: the gem loads only in production, where the app really does sit behind the Cloudflare tunnel, and whether `remote_ip` actually resolves correctly through it is one of the things that dry-run against a preview deploy checks, not something a request spec can exercise.

## Why production emits HSTS without redirecting or preloading

[[config/environments/production.rb]] sets `config.assume_ssl = true` and `config.force_ssl = true` with `redirect: false` and `preload: false` because Cloudflare terminates TLS at the edge.

Cloudflare redirects plain HTTP traffic before it reaches the origin and forwards requests with `X-Forwarded-Proto: https`. Disabling Rails's own HTTP-to-HTTPS redirect prevents health checks on `/up` and internal container probes from being redirected, while emitting `Strict-Transport-Security: max-age=31536000; includeSubDomains` without `preload` avoids permanently locking every subdomain into the browser HSTS preload list.

## Why CloudflareConnectingIpMiddleware normalizes X-Forwarded-For before RemoteIp

[[app/middleware/cloudflare_connecting_ip_middleware.rb#CloudflareConnectingIpMiddleware]] runs before `ActionDispatch::RemoteIp` to pin `HTTP_X_FORWARDED_FOR` to `HTTP_CF_CONNECTING_IP` and strip `HTTP_FORWARDED`.

Because `cloudflare-rails` adds all Cloudflare edge CIDR blocks to `config.action_dispatch.trusted_proxies`, requests originating from Cloudflare WARP or Workers egress addresses arrive from IPs inside those trusted ranges. Without normalization, `ActionDispatch::RemoteIp` treats the caller's WARP or Worker address as another trusted proxy hop and trusts any spoofed address prepended to `X-Forwarded-For` or `Forwarded`. Replacing `HTTP_X_FORWARDED_FOR` with the single verified address from `HTTP_CF_CONNECTING_IP` and stripping `HTTP_FORWARDED` and `HTTP_CLIENT_IP` ensures `ActionDispatch::RemoteIp` resolves `request.remote_ip` to the true client IP.
