---
lat:
  mode: explanation
---

# Query parameter namespaces

Query parameters belong to features rather than individual screens or pages, preventing collisions when navigation carries state across different parts of the application.

## Feature-based ownership

A query parameter is scoped to a feature rather than an individual screen or route.

When state persists across navigations, screen-level naming causes collisions because different screens naturally select identical generic names such as `tab`, `search`, `sort`, `direction`, and `page`. A navigation carrying a generic parameter like `tab=history` from Legislators into Notifications corrupts the destination's active tab. Scoping ownership to features creates clear isolation boundaries where parameter state can travel safely between screens of the same subsystem without polluting unrelated screens.

## Criteria for a feature

A feature is a cohesive functional subsystem with a unified domain model, shared business logic, and an aligned user lifecycle.

In this architecture, an individual route or tab does not constitute a feature on its own. For example, the Bill Creator spans four distinct tab views across multiple routes (`/admin/bill_creator/:id/pipeline`, `/admin/bill_creator/:id/summary`, `/admin/bill_creator/:id/positions`, and `/admin/bill_creator/:id/history`), yet represents a single feature. Switching between these tabs preserves the active pipeline state, selected stages, and parameter context because they belong to one feature boundary.

Future parameters are classified under an existing feature if their lifecycle and domain model are shared with that subsystem, or assigned a new feature prefix if they introduce an independent capability.

## Decided prefix namespaces

Each functional subsystem owns an explicit prefix namespace for all query parameters under its control.

The established namespace mappings are:

- **Bill Creator (`bill_creator_*`)**: Owns `bill_creator_tab`, `bill_creator_sort`, `selected_stages`, `download_missing_assets`, `subject`, `severity`, `window`, `cursor`, `date`, and `highlight`, with `tab_key` (for `bill_creator_tab`) and `stages` (for `selected_stages`) retained as legacy aliases.
- **Bills Catalog (`bills_*`)**: Owns `bills_sort`, `bills_direction`, `bills_page`, `bills_search`, and `bills_legislative_session_id`, with `sort`, `direction`, `page`, `search`, and `legislative_session_id` as legacy aliases.
- **Legislators (`legislators_*`)**: Owns `legislators_tab` and `legislators_search`, with `tab` and `search` as legacy aliases.
- **Notifications (`notifications_*`)**: Owns `notifications_tab`, with `tab` as a legacy alias.
- **Organizations (`org_*`)**: Owns `org_tab`, with `tab` and `tab_key` as legacy aliases.
- **Feed (`feed_*`)**: Owns `feed_search` and `feed_cursor`.

Parameters that cross subsystem boundaries and maintain app-wide ambient context (`sway_locale_id`, `run_id`, and `highlight_bill_id`) belong to the global ambient parameter group rather than an individual feature namespace.

## Backward compatibility and dual-reading

Shared bookmarks and existing external links require persistent support through dual-reading.

When an incoming request arrives, controllers and frontend hooks inspect the canonical namespaced parameter first. If the canonical parameter is absent, reading falls back to the legacy alias. When both canonical and legacy parameters are present in the same query string, the canonical namespaced parameter takes precedence and the legacy parameter is discarded; an explicitly empty canonical membership tab therefore defaults to Positions without reading a nonempty alias.

During centralized navigation carry, this dual-reading convention interacts with operator intent. When a destination link explicitly supplies a legacy alias (such as `search=housing`), carrying an implicit canonical parameter (such as `bills_search=zoning`) would cause backend canonical precedence to overwrite the operator's intentional destination selection. The interceptor therefore suppresses carrying canonical parameters when the destination specifies any equivalent legacy alias from the parameter family. When the destination explicitly supplies both keys, the interceptor leaves them untouched, allowing canonical precedence to govern on the server.

This dual-reading contract ensures that links generated prior to namespacing continue to resolve accurately without breaking user bookmarks or external referrals.

The Legislators subsystem (`app/controllers/legislators_controller.rb` and `app/frontend/pages/Legislators.tsx`) dual-reads `legislators_tab` and `legislators_search` with fallback to `tab` and `search`. Interactive URL updates on the Legislators page and in `useDebouncedUrlSearch` write canonical parameters while deleting legacy aliases.

The Bills subsystem (`app/controllers/bills_controller.rb` and `app/frontend/pages/Bills.tsx`) dual-reads `bills_sort`, `bills_direction`, `bills_page`, `bills_search`, and `bills_legislative_session_id` with fallback to `sort`, `direction`, `page`, `search`, and `legislative_session_id`. Interactive URL updates on the Bills list, `useUrlSort`, and `useDebouncedUrlSearch` write canonical parameters while deleting legacy aliases.

The Organizations subsystem uses `org_tab` for membership-view state, reads legacy `tab` and `tab_key` only when the canonical key is absent, and writes only the canonical key from its membership page. Its membership index and detail keep the existing `tab` response prop. Shared list hooks require each caller to name its owned search, sort, and direction parameters; the Bills list supplies its `bills_*` names and legacy aliases explicitly.

## Machine-readable registry and lint enforcement

The canonical mapping of features, parameters, route patterns, and semantic alias families lives in a structured registry configuration file.

The machine-readable definition resides at `config/query_parameters.yml`. It declares feature-owned parameters, route patterns, aliases grouped under each canonical parameter, and global ambient parameters. The frontend derives its carry registry from the same projection, and a parity spec checks the normalized backend/frontend structures.

Route patterns are limited to a shared ASCII regex subset used by Ruby and JavaScript, including ordinary anchors, character classes, and lookahead. The registry rejects Ruby-only escapes, POSIX character classes, class intersections, and nonstandard group forms before the backend and frontend can interpret them differently.

A dedicated Rake lint task (`sway:lint:param_names`), executed as part of the verification gate, validates registry shape and ownership collisions. It checks registry declarations; it does not scan controller or hook reads for conformance.
