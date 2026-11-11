---
lat:
  mode: explanation
---
# The drawer header and nav selection

Below 1024px the sticky bar at the top of every signed-in page carries the hamburger button and the name of the page the reader is on. That name and the sidebar's "you are here" highlight are both derived from one rule over the nav items.

## Where the mobile header's page name comes from

[[app/frontend/components/drawer/Drawer.tsx#pageTitleFor]] asks the nav first and the placeholder registry second, so the header repeats the wording the reader just tapped rather than a second name for the same page.

The nav items are built in `AuthLayout` and already carry a label and a route, and the drawer already works out which one is selected in order to set `aria-current`. Reading that selected item's label costs no new plumbing and keeps one string per destination: a rename in the nav renames the header with it.

Most pages a reader reaches are not in the nav — a bill, a legislator, an organization membership. Those fall through to `resolvePlaceholder` in `app/frontend/navigation/placeholderRegistry.ts`, the map that already names a pathname for the loading announcement, so the second name for a page is the one the reader was already told while it loaded.

One consequence reaches the tests: the header repeats the selected item's label, so the label now appears twice in the rendered markup — once as a nav link and once as the title. A test that asks for the text alone finds both, which is why the `AuthLayout` nav assertions ask for the link.

The registry's generic entry names a page "page", which is a placeholder announcement rather than a title, so an address matching nothing shows "Sway". That line used to read "Drawer Navigation" on every page and every phone, naming the component the developer was building.

## Why the selection rule strips the query and hash

[[app/frontend/components/drawer/Drawer.tsx#isItemSelected]] compares against a pathname with `?` and `#` removed, matching the same normalization in `AuthLayout`, because an address like `/admin/llm_settings#models` would otherwise miss its highlight.

An `activePrefix` takes priority over an exact route match. Parent entries set it so the sidebar stays lit across child routes — `/admin/bill_creator/42/edit` keeps Bill Creator selected — while `isActivePrefix` holds the prefix to a path-segment boundary so a sibling namespace such as `/admin/bill_creator_archive` does not light it too.

External entries are excluded from the title lookup: their route is an absolute URL, which no pathname matches, and a GitHub link is not a page of Sway.

## Why ThemeToggle omits aria-pressed and shares the mobile cycle order

[[app/frontend/components/drawer/ThemeToggle.tsx#ThemeToggle]] cycles through `light`, `system`, and `dark` in the same order as the mobile appearance control and announces both the current mode and the next mode in `aria-label` rather than setting `aria-pressed`.

Because `aria-pressed` models a two-state toggle, applying it to a three-state cycle would misreport the control's state to assistive technologies.
