---
mode: explanation
summary: "Why the admin locales page exists as a separate view from the general nav selector"
status: agent-extracted
related: []
---

# Admin locales page: registration visibility

`Admin::LocalesController#show` renders every `SwayLocale`, grouped by tier
(city/state/Congress), with the number of registered users. Sway
auto-creates a locale for any registration address (`Address#sway_locales`),
so this is the admin-only view of where sign-ups land — including outside
the actively-supported set — which the general nav selector no longer shows.

## Why one user can count toward three locale rows

A user belongs to the three locales its address resolves to (city, state,
congress), so a Baltimore user counts toward Baltimore, Maryland, AND U.S.
Congress.

## Why LocaleUserCountsService matches against existing locale rows

Moved to `lat.md/explanation/locale-user-counts.md`, which also covers how the
count is taken now that it no longer walks every user.
