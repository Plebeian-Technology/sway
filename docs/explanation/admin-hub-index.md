---
mode: explanation
summary: "Why the /admin hub exists, why it follows the Admin::* controller convention, and how the tools list is expected to grow"
status: agent-extracted
related: []
---

# The /admin hub

The `/admin` hub (`Admin::IndexController`) is one index page that
lists every admin tool. It exists so no admin tool ships without a
discoverable link — the LLM Settings page once had no link anywhere, and
admins had to type its URL by hand. The nav drawer's "Admin" entry
(`AuthLayout` `secondaryItems`) points here.

It follows the `Admin::*` convention: it inherits from `ApplicationController`
directly (no `Admin::BaseController`), and — like every `Admin::*`
controller — must declare its own `before_action :verify_is_sway_admin` and
add its path to `lib/tasks/sway_lint.rake`; lint fails CI if either is
missing.

This controller renders pure Inertia — no JSON shape today. A future mobile
admin client would re-add `render_inertia_or_json` here.

## Why the tools list is built server-side

`#show` renders the hub with a server-built tools list so a future role
system (sub-admin / org-admin / etc.) can filter it without a frontend
rewrite.

## `admin/Index.tsx`, the frontend hub page

The page is intentionally restrained — the sidebar carries the primary nav;
the content area just confirms where the operator is and offers quick links
so a fresh admin can see what's available at a glance. This page is the
destination of the renamed Drawer entry ("Creator" -> "Admin"). `AuthLayout`
switches to the admin sidebar navigation whenever any `/admin/*` route is
active.

`GROUP_ORDER` gives stable section ordering — controller groups are
free-form strings, but the page renders them in this order. Unknown groups
fall through to the end in the order the controller emitted them.

`ToolCard`'s external-link branch checks `isSafeExternalHref` a second time
as defense in depth: the outer group filter in `Index.tsx` already removes
unsafe external tools before they reach this branch (so an empty group
heading never renders either), but the `return null` here stays as a second
guard in case a future call site skips that filter. Likewise, if every tool
in a group fails the safe-href guard (or any future filter), the section
would otherwise show an empty heading; `Index.tsx` hides it entirely so the
operator doesn't see a confusing empty "Data" or "Settings" section.

The grouped and sorted tools list is memoized so the `Map` and sort do not
rebuild on every render — a small win with only 2-3 tools, but cheap.

## Tool shape and adding a new tool

Each tool ships to the frontend with: `id` (for React keys), `label`,
`description` (the one-liner under the label), `path` (Inertia link target),
`group` (sub-heading on the page), and `external` (true means render a plain
anchor that opens in a new tab — unused today, reserved for tools that link
out to monitoring dashboards and the like).

Adding a new admin tool: append a Hash to the `tools` array. No per-role
gating exists yet — `verify_is_sway_admin` is the only gate. When
sub-admin/org-admin roles ship, replace this with a `tools_for(user)` that
filters by role; adding that parameter is then a one-line change here plus
the call site.
