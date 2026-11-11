---
lat:
  mode: explanation
---

# Theme mode and theme id resolution

`ThemeHelper` (`app/helpers/theme_helper.rb`, included into `ApplicationController`) resolves two separate settings before the first paint, so the server can write the right values straight into the `<html>` tag.

## Mode: auto, light, or dark

Checked in this order:

1. Signed in — `users.theme_mode` (the DB column).
2. Anonymous — the signed `sway_theme` cookie, written by
   `Users::PreferencesController#update`.
3. Default — `"light"`.

## Theme id: sway, classic, chamber, and so on

The server reads the signed `sway_theme_id` cookie. It deliberately has no DB column — carrying the chosen theme id across devices is out of scope. Default is `"sway"` (a light-mode theme).

## Why update skips the auth gate

Anonymous visitors can also save a theme preference (signed cookie).

The DB write only happens for signed-in users; the anonymous path writes the cookie alone. `Users::PreferencesController#update` skips `authenticate_sway_user!` so the cookie-only path works for anonymous callers too.

## Why a successful update uses redirect_back, not a fixed path

`redirect_back_or_to("/profile", ...)` keeps the user on whatever page triggered the toggle — the old fixed `/profile` redirect yanked users off the page they were on every time they cycled themes.

Mobile callers still get the JSON `{redirect, flash}` envelope instead of a real redirect.

## Why validation failures redirect back with an Inertia errors prop, not a plain redirect

A plain `redirect_to "/bills"` with a flash alert looks like a SUCCESS to Inertia — it never fires `useTheme`'s `onError` rollback, and it yanks the user to `/bills`.

`render_preference_errors` uses `redirect_back_or_to + inertia: {errors:}` instead, which keeps the operator in place (matching the success path) and makes the theme rollback reachable.

## Why no JavaScript is needed for auto mode

The layout emits `<html data-theme="<%= theme_id %>" data-theme-mode="<%= theme_preference %>">`, so the very first paint already uses the right design tokens.

CSS handles `"auto"` mode itself via `@media (prefers-color-scheme: dark)` — see [[docs/explanation/use-theme-server-driven-no-effect.md|useTheme is server-driven, not effect-driven]] for how the frontend hook builds on this same resolution.
