---
mode: explanation
summary: "Why sway_locales, sway_locale_options and admin_sway_locale_options must never be Inertia once-props, and the leak in both directions that resulted when one of them was."
status: agent-extracted
related: []
---
<!-- vale Vale.Spelling = NO -->

# Why per-user locale props are never once-props

`sway_locales`, `sway_locale_options` and `admin_sway_locale_options` are
all built **per user** — the first two from `locales_for_current_user`,
the third from `current_user&.is_sway_admin?` — so none of them may be a
once-prop that the client caches.

## What a once-prop is, and why that breaks here

A once-prop is sent on the first response and then left out whenever the
client says it already holds the value, through the
`X-Inertia-Except-Once-Props` header. The client never clears that cache
by itself: `clear_history` does not touch once-props, and signing in and
signing out are both redirects inside the single-page app, so no full
page load ever resets it.

That breaks in both directions:

- A guest is offered every jurisdiction, signs in, and goes on being
  offered jurisdictions they have nothing to do with.
- A signed-in user signs out, leaving their own jurisdiction list on
  screen for whoever sits down next.

## The fix

Stop marking these props `once`, rather than force a full page load at
sign-in and sign-out. `once` is a cache with no key, and these values
depend entirely on who is asking. `locales_for_current_user` is a single
memoized association read, so rebuilding it on every response costs a
query the request already runs for the navigation bar.

All three locale props are checked, not only the two first reported: the
problem is the caching mechanism itself, and all three used it.

## Why `sway_locale_options` and `admin_sway_locale_options` exist as separate props

`sway_locale_options` ships ready-made `{label, value}` option pairs for
locale `<Select>` controls (`AdminLocaleSelector` and friends), computed
from `locales_for_current_user` via `SwayLocale#to_select_option` — the
client renders these as-is instead of re-deriving display names from
locale names.

`admin_sway_locale_options` exists because the admin Bill Creator needs
every locale, and `sway_locale_options` only ever carries the signed-in
user's own. It resolves to `nil` for anyone who is not a Sway admin
(`current_user&.is_sway_admin?`), so the full locale list never reaches
non-admin pages.

## Why `useLocales` falls back to empty arrays

`useLocales` (`app/frontend/hooks/useLocales.ts`) reads `sway_locales` and
`sway_locale_options` off shared props and returns `?? []` for each. A
page rendered outside the normal shared-props pipeline (tests, error
pages) may still not have them, hence the fallbacks.

## Why `locales_for_current_user` excludes admins from the full list

`locales_for_current_user` — the set shown in the nav's locale selector —
returns only the locales a signed-in user belongs to, admins included.
Admins reach the full list through `admin_sway_locale_options` (Bill
Creator) and `/admin/locales` instead. Logged-out visitors belong to no
locale, so they get every locale to browse.

## Why AdminLocaleSelector is the jurisdiction switcher for the admin Bill Creator

V2 initially shipped without one, leaving admins stuck with the jurisdiction
they registered in.

Only draws the control, like its neighbour BillPickerSortToggle — the shell
handles navigation and the unsaved-changes guard, through
onSwayLocaleChange.

The server already obeys ?sway_locale_id=N
(ApplicationController#find_current_sway_locale) and saves it to a
long-lived cookie.

Choices come from useAdminLocaleOptions — the admin-only list of every
jurisdiction — not from useLocales, which shows only the jurisdictions the
operator belongs to.

The Bill Creator needs to reach all of them, to create bills anywhere.

### Why AdminLocaleSelector tracks a pending locale separately from the confirmed one

useLocales.ts's usage rule: render the picker's value as
`pendingSwayLocaleId ?? locale?.id`.

Binding only to the confirmed locale binds to server state — React would
snap back to the old choice immediately, before the redirect lands
(measured 1.6s against a slowed test server).

BillCreatorShell owns this: it's the one place that knows whether the
navigation is pending, cancelled, or done.
