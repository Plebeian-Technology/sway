---
lat:
  mode: explanation
---

# Admin locales page: registration visibility

`Admin::LocalesController#show` renders every `SwayLocale`, grouped by tier (city/state/Congress), with the number of registered users.

Sway auto-creates a locale for any registration address (`Address#sway_locales`), so this is the admin-only view of where sign-ups land — including outside the actively-supported set — which the general nav selector no longer shows.

## Why one user can count toward three locale rows

A user belongs to the three locales its address resolves to (city, state, congress), so a Baltimore user counts toward Baltimore, Maryland, AND U.S. Congress.

## Why LocaleUserCountsService matches against existing locale rows

Moved to `lat.md/explanation/locale-user-counts.md`, which also covers how the count is taken now that it no longer walks every user.

## Why admin authoring and prompt previews scope to declared locales

Admin bill authoring and system prompt previews restrict locale lists to [[app/models/sway_locale.rb#SwayLocale|SwayLocale.declared]], while `/admin/locales` continues rendering every persisted row.

Undeclared locale rows auto-created during user registration lack jurisdiction rules and legislative metadata. Presenting unsupported cities in bill authoring dropdowns (`admin_sway_locale_options`) or prompt previews (`AdminSystemPromptCatalog`) generates broken drafts and empty prompt templates. Persisted undeclared rows remain visible exclusively on `/admin/locales` to monitor sign-up distribution.
