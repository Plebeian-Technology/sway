---
mode: explanation
summary: "Why LocalePicker resolves its select styling through useActiveThemeId and a per-theme class map, rather than each caller styling its own control."
status: agent-extracted
related: []
---

# Why `LocalePicker` resolves its own theme styling

`LocalePicker` is the one locale picker used everywhere a reader switches
jurisdictions (bill-list layouts, Legislators, Bill of the Week,
Influence), so it always carries the active theme's look. It
resolves the theme through `useActiveThemeId`, so it re-styles itself
instantly when the theme changes, without a page reload.

`THEME_SELECT_CLASSES` lists themes that style their own controls. An
unlisted theme (sway, classic) uses the default "neo" look those themes
already render — so adding one here is the entire styling cost.

Classes come from `styles/theme-selects.css` (global). List layouts'
sort/search selects share these classes so a theme's picker can't
visually drift from the controls beside it.

## Why `NEO_SELECT_CLASS` is a class, not a component

`NEO_SELECT_CLASS` (`app/frontend/components/ui/LocaleSelect.tsx`) is the
neo `<select>` chrome, shared by the sway/classic themes' native selects
(the default bill-list layout's sort and search controls) without
re-copy-pasting the string.

It is also what `LocalePicker` falls back to for any theme that does not
dress its own controls, which is why it is a class rather than a
component: the themed selects are CSS classes in
`styles/theme-selects.css`, and the picker chooses between them by theme
id.
