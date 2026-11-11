---
lat:
  mode: explanation
---

# useTheme's setThemeId rollback invariant

`setThemeId` (`app/frontend/hooks/useTheme.ts`) paints a theme id change on `<html data-theme>` immediately, from the click handler — not from a `useEffect` (see [[docs/explanation/use-theme-server-driven-no-effect.md|useTheme is server-driven, not effect-driven]] for why).

It then sends the change to the server via `PATCH /users/preferences`.

`setThemeId` accepts any `ThemeId`, but the server's allowed-id list (`preferences_controller.rb`) can refuse one — for example after a cookie or secret rotation, or when a new id has landed in TypeScript but not yet on the Ruby side. When the server rejects the change, the handler rolls back to `serverThemeId`, a value captured from `props.theme?.id` at the start of the call — the single source of truth for what the server actually has stored.

The rollback deliberately does not read `document.documentElement.dataset.theme` back off the page to decide what to restore. That value doesn't survive two writes overlapping: if a second `setThemeId` call fires while the first is still in flight, it may already have painted its own guess onto the attribute by the time the first call's `onError` runs, and reading it back would restore the wrong theme. The captured `serverThemeId` is stable for the render regardless of what happens concurrently.

If `data-theme` was not present on the element before this call (test mounts and other renders that skip the server-rendered layout), the rollback removes the attribute instead of writing a rejected id in its place — otherwise the page would show a theme the server never saved, which would then silently snap back on the next navigation. A manual reload should never be part of any workflow.

## Why setPreference protects itself the same way

`setPreference` remembers the current mode before touching anything, so its own `onError` can put it back — the same protection `setThemeId` has.

The only caller today (`ThemeToggle`) sends values the Ruby side already allows, so the server cannot reject this right now. But a future caller could send a mode the server's allowed list does not have, and then the guess painted on screen would stay stuck until the user reloaded the page — and a reload should never be part of a workflow.

## Why setThemeId exists before anything calls it

Nothing calls `setThemeId` yet.

It is here for the theme-picker screen coming in a later release, which will be the first real caller; adding the handler now means `useTheme()`'s shape will not have to change then. `useTheme.test.ts` covers it.
