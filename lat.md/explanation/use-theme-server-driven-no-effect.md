---
lat:
  mode: explanation
---

# useTheme is server-driven, not effect-driven

`useTheme` (`app/frontend/hooks/useTheme.ts`) reads the active theme out of the shared Inertia props (`theme.preference`) rather than computing it on the client.

The server picks the value in this order: the signed-in user's `users.theme_mode`, then a signed cookie for logged-out visitors, then `"light"`.

## Why there is no useEffect, useState, or localStorage listener

Server-driven HTML attribute rendering and CSS media queries eliminate client-side state flicker and effect execution on load.

- **Looks.** The server writes `<html data-theme-mode="…" class="dark|">`
  before the first paint. For the `"auto"` setting, CSS decides via
  `@media (prefers-color-scheme)` — no JavaScript is involved in picking the
  resolved look.
- **Toggling.** The click handler flips the `<html>` attribute and class
  itself so the change is instant, then `PATCH`es `/users/preferences` (that
  request answers with a redirect back to the current page).
- **The user changing their OS appearance while the page is open.** The same
  CSS `@media` rule covers this for the `"auto"` setting, so no JavaScript
  listener is needed. Nothing in the React tree needs the resolved
  light/dark value in JS today — if that changes, add a
  `useEffectiveMode` hook built on `useSyncExternalStore` rather than an
  Effect.

## Further reading

This pattern follows the React docs' guidance on [You Might Not Need an Effect](https://react.dev/learn/you-might-not-need-an-effect).

This pattern follows the React docs' guidance on [You Might Not Need an Effect](https://react.dev/learn/you-might-not-need-an-effect), specifically the "Subscribing to an external store" section (the outside store here is the CSS `@media` state, which the browser owns) and "Sharing logic between event handlers".

## Why "system" and "auto" are different names for the same thing

The web code calls the follow-the-OS setting `"system"`; the server calls the same thing `"auto"`.

`useTheme` is the ONLY place that translates between the two names — `toServer`/`fromServer` turn the web's `"system"` into the server's `"auto"` and back; `"light"` and `"dark"` pass straight through unchanged.

## Why fromServerId checks against isValidThemeId instead of its own list

`fromServerId` checks the id with `isValidThemeId` from `themes/index.ts` — the one check backed by the real `THEMES` list — rather than keeping a second copy of the valid ids here.

## Why the PATCH request options are what they are

Saving a theme change goes through Inertia's post-then-redirect flow.

The controller writes the signed cookie for logged-out visitors and updates `users.theme_mode` for signed-in ones. `preserveState` keeps whatever is typed into forms, `preserveScroll` stops the page jumping, and `only: []` means the page redirected to does not re-fetch props nothing here needs.

## Why font_hrefs stays snake_case

`font_hrefs` (on the shared `theme` prop) is a straight copy of Ruby's `ThemeHelper::THEME_FONT_HREFS`. The key stays snake_case because Inertia hands Ruby hash keys over exactly as they were written.

## Why the webfont link is swapped in the same click handler

The webfont `<link>` sits in the `<head>` of the ERB layout.

The webfont `<link>` sits in the `<head>` of the ERB layout, and an Inertia partial visit never re-renders that, so `setThemeId` swaps it in the same handler that sets `data-theme`, and the fonts change at the same moment as the colors instead of waiting for a full page load.
