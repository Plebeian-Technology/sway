---
lat:
  mode: explanation
---

# Why external asset mirroring is built the way it is

Every mirrored picture — a legislator portrait, an organization icon — starts on somebody else's server.

`ExternalAssetMirrorService` copies it into Sway's own storage; `MirroredAssetUrl` works out which address to hand the browser once that copy exists. See [[docs/explanation/mirrors-external-asset-concern.md|mirrors-external-asset-concern.md]] for the shared concern that decides WHEN a copy job is queued in the first place.

## ExternalAssetMirrorService

Service architecture responsible for safely downloading and caching third-party media assets into Sway storage.

### Why ASSETS_BUCKET is not named here

`ASSETS_BUCKET` is named in `deploy/config/sway.env`, not here — it identifies a deployment-specific cloud account and this repo is public.

### Why MAX_DOWNLOAD_BYTES exists

The download size is capped so a hijacked or misbehaving upstream cannot exhaust memory or disk on the single Raspberry Pi that runs production. Legislator portraits and org icons are well under 10 MB.

### Why RESERVED_INTERNAL_RANGES exists

`0.0.0.0` and `::` (and the whole `0.0.0.0/8` "this host on this network" block) along with Carrier-Grade NAT / Tailscale (`100.64.0.0/10`) are not caught by `private?`/`loopback?`/`link_local?`, yet reach internal or non-routable networks.

`RESERVED_INTERNAL_RANGES` in [[app/services/external_asset_mirror_service.rb#ExternalAssetMirrorService]] blocks `0.0.0.0/8`, `100.64.0.0/10`, documentation ranges, multicast, and broadcast blocks matching `BLOCKED_CIDR_RANGES` in [[app/services/news_article_text_fetch_service.rb#NewsArticleTextFetchService]], and `ALLOWED_IMAGE_CONTENT_TYPES` restricts mirrored attachments to image MIME types (`image/jpeg`, `image/png`, `image/webp`, `image/gif`, `image/svg+xml`, `image/avif`).

### Why upstream hosts are checked for private/loopback/link-local addresses

Rejecting upstreams that resolve to private, loopback, or link-local addresses blocks SSRF (tricking the server into fetching internal addresses).

Rejecting upstreams that resolve to private, loopback, or link-local addresses blocks SSRF (tricking the server into fetching internal addresses) — a server that fetches user-supplied URLs must not be able to reach hosts on its own private network. Enforced only in production so the dev `IS_DOCKER` localhost→web rewrite still works.

`#private_or_local_host?` fails closed: an unparseable URL or unresolvable host is treated as private. A literal-IP host is its own address; a name is resolved via DNS, and a name that resolves to nothing also fails closed (an empty address list).

`spec/services/external_asset_mirror_service_spec.rb`'s `"the container switch (IS_DOCKER)"` context exercises the dev `IS_DOCKER` localhost→web rewrite directly: a `localhost` upstream, read from inside the Rails container, has to reach the `web` container by name instead. The production SSRF guard above never runs in that spec's environment (test), so the container switch is the only thing standing between the two URLs.

### Why URLs are normalized before download

Some upstream photo URLs contain spaces or other unencoded characters (e.g.

legislator portrait paths), which Down/URI reject as an "Invalid Redirect URI". Percent-encoding them before download lets them resolve instead of silently failing to mirror.

### Why redirects are walked by hand instead of left to Down

Down's open-uri backend follows redirects internally WITHOUT exposing the intermediate `Location`, so a redirect to a private/LAN host would slip past the initial-URL guard.

`#resolve_final_url` closes that hole by walking the redirect chain itself, checking every hop's target against the same guards as the initial URL, up to `max_hops` redirects (the same limit Down previously applied itself), then handing the final URL to Down with its own redirect-following DISABLED (`max_redirects: 0`). The size cap still bounds the actual download.

`#redirect_location_for`'s probe is a GET that reads headers only — the block closes the connection (`conn.finish`) and returns before `Net::HTTPResponse#reading_body` can drain the body, so no bytes beyond the headers cross the wire. GET (not HEAD) matches exactly what `Down.download` will fetch, which matters for upstreams that answer HEAD and GET differently. A hop that cannot be probed (DNS failure, timeout, reset) is treated as final: the caller returns the last validated URL and Down attempts it with redirects disabled — never a silent unvalidated fetch.

`#absolute_redirect_target` re-encodes a `Location` header carrying a raw space (a sloppy but real server behavior) instead of letting `URI.join` raise before the redirect target's safety can be decided. Browsers and curl re-encode it and carry on; this does the same.

### Why url_column is never overwritten with a local storage-proxy URL

`url_column` keeps pointing at the external upstream, which stays the source of truth; consumers fetch directly from it.

The local ActiveStorage attachment is still made as a future-use fallback. This method used to overwrite `url_column` with a local storage-proxy URL, which baked the dev hostname (`localhost:3000`) into the DB — once the local blobs were wiped (`dip compose down --volumes`), those URLs were dead links, and a re-mirror could only re-fetch the dead local URL.

### Why a 404 from the upstream does not clear url_column

Many upstream sites (baltimorecitycouncil.com, msa.maryland.gov, etc.) move their file paths often, and Down reports a redirect-to-error as `NotFound`.

Nulling the DB column on every passing 404 would erase the source-of-truth URL that came from seed JSON, with no way to recover short of a manual reset. The attachment may have been left half-attached; it is purged to keep state consistent, but the URL is kept.

## MirroredAssetUrl

URL resolution helper generating stable, secure paths to mirrored external assets with fallback to original sources.

### Why the browser is pointed at the local copy at all

Nothing used the copies `MirrorsExternalAsset` produces before this class existed, so the browser still went out to the other server for every face on the page.

Serving Sway's own copy instead lets the browser reuse the connection it already has open to Sway — no second name lookup, no second handshake — and the request passes through Cloudflare, which can then keep the file close to the reader.

### Why the address column is left alone

The address column is deliberately left alone.

It stays the source of truth and keeps pointing at wherever the picture came from. Storing Sway's own address in it was tried once and undone: it wrote the development machine's name into the database, and deleting local files left those rows pointing at nothing. So the address is worked out here, while the page is built, and never saved — the same lesson `ExternalAssetMirrorService` learned on the write side (see above).

`#for` uses two separate `return` guards rather than one condition. A `return` guard is the only form Steep reads as ruling out nil, so this is what lets the call below type-check without weakening the signature.

A half-made copy or a missing site name must never cost the reader the whole page — `#for`'s rescue sends them where the picture came from instead.

### Why a bare bucket key falls back to a constructed bucket URL

Some organizations' fallback column holds a bare bucket file name instead of an address, a stray write that skipped building the URL.

With no scheme and no single leading `/` (protocol-relative `//` is excluded) it cannot be a real or site-relative address, so `#external_fallback_url` treats it as a name inside Sway's own assets bucket rather than handing back an unusable string. Explicit URI schemes that are not standard web protocols (such as `file:`, `javascript:`, or `data:`) are rejected and return nil to prevent browsers from attempting to load or prefetch local or unsafe file URIs.

### Why route options win over mailer options

`#url_options` merges the route settings on top of the mailer settings.

The route settings win, because in development they are the only ones the browser can reach: the mail settings there name port 3000, which is the Rails container, while the browser talks to Caddy on port 3333 over https. An address on port 3000 is a different origin, and the browser refuses to load it. The mail settings still supply the host name under test, where the route settings carry a protocol and no host. In production the two are set from the same values, so the order does not matter there.
