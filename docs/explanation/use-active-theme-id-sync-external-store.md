---
mode: explanation
summary: "Why useActiveThemeId reads the visual theme id from the <html data-theme> attribute via useSyncExternalStore instead of the Inertia theme.id prop."
status: agent-extracted
related: [docs/explanation/use-theme-server-driven-no-effect.md, docs/explanation/theme-mode-and-theme-id-resolution.md]
---

# useActiveThemeId reads the DOM, not Inertia props

`useActiveThemeId` (`app/frontend/hooks/useActiveThemeId.ts`) treats the
`<html data-theme>` attribute as the single source of truth for the active
visual theme — as opposed to `theme.preference` (the light/dark/system
mode), which `useTheme` covers separately.

The server-rendered (ERB) layout sets `data-theme` on first paint.
`useTheme().setThemeId` updates it optimistically afterward, before waiting
for a server response. Reading the DOM attribute directly, instead of the
Inertia `theme.id` prop, means a theme switch from the picker updates any
dependent UI immediately, in step with the CSS re-skin, with no page
navigation or round trip through props needed.

## Why `useSyncExternalStore`, not `useEffect` + `useState`

Following React's own guidance ("You Might Not Need an Effect"), the
`<html>` attribute is treated as an external store that this hook
subscribes to via a `MutationObserver`, rather than polled from inside an
effect. `useSyncExternalStore` is the tool React provides for exactly this
case.
