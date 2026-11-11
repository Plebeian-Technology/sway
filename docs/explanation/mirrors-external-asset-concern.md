---
mode: explanation
summary: "Explains why MirrorsExternalAsset exists as a shared concern, when it skips queuing a copy job, and two bugs around URLs with no host."
status: agent-extracted
related: [docs/explanation/mirrored-asset-query-cost-coverage.md, docs/explanation/legislator-photo-repair-interlock.md]
---
<!-- vale Vale.Spelling = NO -->

# Why MirrorsExternalAsset is a shared concern

When a record points at an image hosted somewhere else, Sway can copy that
image into its own storage. `Legislator` uses this for `photo` / `photo_url`,
and `Organization` uses it for `icon` / `icon_url`. A former `SwayLocale`
declaration was removed because no reader resolves a locale icon attachment;
its `icon_url` remains jurisdiction metadata sent to clients.

`ExternalAssetMirrorService` keeps its own, separate list of hosts that
count as "already ours," used by a different skip path elsewhere in that
service. This concern's `internal_asset_url?` does not merge that fourth
copy in — the two lists are allowed to diverge.

## When the copy job is skipped

`mirrors_external_asset(attachment_name:, url_column:)` sets up an
`after_commit` hook that fires only when `url_column` actually changed
(`saved_change_to_#{url_column}?`), and even then only enqueues a copy job
when `internal_asset_url?` says the new URL points somewhere Sway does not
already host: anything on a `sway.vote` subdomain, or already inside
Sway's own assets bucket on `storage.googleapis.com`, is skipped.

### Why a blank host counts as already-internal

`internal_asset_url?` treats a URL with no host as already internal —
either a storage bucket key (34 organizations hold one) or an app-relative
path like `/images/sway-us-light.png`. Both used to queue a copy job that
could only refuse to do anything, since there is nothing to fetch when
there is no host to fetch it from.

Skipping the copy for these is correct, but it has a side effect: because
no mirrored copy is ever produced for a bare key, the value passed to a
reader expecting a fetchable URL is that same bare key, unusable as one —
34 icons silently fail to render as a result. This check runs
BEFORE the HTTP-scheme test, not instead of it: a protocol-relative URL
like `//example.com/x.png` DOES have a host and is still treated as an
outside source.
