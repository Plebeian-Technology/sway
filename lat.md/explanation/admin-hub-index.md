---
lat:
  mode: explanation
---

# The /admin hub

The `/admin` hub (`Admin::IndexController`) is one index page that lists every admin tool.

It exists so no admin tool ships without a discoverable link — the LLM Settings page once had no link anywhere, and admins had to type its URL by hand. The nav drawer's "Admin" entry (`AuthLayout` `secondaryItems`) points here.

It follows the `Admin::*` convention: it inherits from `ApplicationController` directly (no `Admin::BaseController`), and — like every `Admin::*` controller — must declare its own `before_action :verify_is_sway_admin` and add its path to `lib/tasks/sway_lint.rake`; lint fails CI if either is missing.

This controller renders pure Inertia — no JSON shape today. A future mobile admin client would re-add `render_inertia_or_json` here.

## Why the tools list is built server-side

`#show` renders the hub with a server-built tools list so a future role system (sub-admin / org-admin / etc.) can filter it without a frontend rewrite.

## admin/Index.tsx, the frontend hub page

The page is intentionally restrained — the sidebar carries the primary nav; the content area just confirms where the operator is and offers quick links so a fresh admin can see what's available at a glance.

This page is the destination of the renamed Drawer entry ("Creator" -> "Admin"). `AuthLayout` switches to the admin sidebar navigation whenever any `/admin/*` route is active.

`GROUP_ORDER` gives stable section ordering — controller groups are free-form strings, but the page renders them in this order. Unknown groups fall through to the end in the order the controller emitted them.

`ToolCard`'s external-link branch checks `isSafeExternalHref` a second time as defense in depth: the outer group filter in `Index.tsx` already removes unsafe external tools before they reach this branch (so an empty group heading never renders either), but the `return null` here stays as a second guard in case a future call site skips that filter. Likewise, if every tool in a group fails the safe-href guard (or any future filter), the section would otherwise show an empty heading; `Index.tsx` hides it entirely so the operator doesn't see a confusing empty "Data" or "Settings" section.

The grouped and sorted tools list is memoized so the `Map` and sort do not rebuild on every render — a small win with only 2-3 tools, but cheap.

## Tool shape and adding a new tool

Each tool ships to the frontend with `id`, `label`, `description`, `path`, `group`, and `external`.

Each tool ships to the frontend with: `id` (for React keys), `label`, `description` (the one-liner under the label), `path` (Inertia link target or external URL), `group` (sub-heading on the page), and `external` (true means render a plain anchor that opens in a new tab, used by the Beszel monitoring dashboard link).

Adding a new admin tool: append a Hash to the `tools` array. `verify_is_sway_admin` gates the controller, while the Beszel monitoring tool is additionally gated on [[app/models/user.rb#User#beszel_url]] ([[app/models/user.rb#User#monitoring_admin?]], see [[admin-hub-index#Who sees the monitoring link]]) and mirrored in [[app/frontend/components/layouts/AuthLayout.tsx#AuthLayout]] when `user.beszel_url` is present.

## Who sees the monitoring link

The Beszel link goes only to a Sway admin whose email domain is listed in `BESZEL_ADMIN_EMAIL_DOMAINS` ([[lib/sway/settings/ops.rb#Ops]]). With nothing listed, no admin sees it.

Admin status comes from a phone number, and every admin can reach `/admin`. The monitoring dashboard shows the serving machine's own address and its health, which is an operator's concern rather than every admin's. An email domain the operator controls is the second fact that separates an operator from an admin, and it is a setting because the domain belongs to one installation. A fork that sets nothing publishes the dashboard address to nobody, which is the safe failure: the dashboard is still reachable directly by whoever runs the machine.

The match is on the whole domain after the last `@`, ignoring case and a leading `@` in the setting, so a listed domain does not also admit a longer domain that ends with it. Production lists the public product domain in `config/deploy.yml`.

## Database and queue health snapshot

[[app/services/admin_database_health.rb#AdminDatabaseHealth]] surfaces SQLite database and WAL file sizes alongside Solid Queue execution counts on `/admin` as a companion to Beszel host metrics.

Because Beszel Agent tracks container and filesystem metrics rather than SQLite internals or Solid Queue tables, [[app/controllers/admin/index_controller.rb#IndexController#show]] passes `database_health` to [[app/frontend/pages/admin/Index.tsx#Index]] so operators can inspect `.sqlite3` and `-wal` sizes across all configured databases alongside ready and failed job counts on the same screen.
