---
lat:
  mode: explanation
---

# ui/Combobox primitive design

Searchable single-select combobox.

A trigger button shows the current selection; opening it reveals a type-to-filter Popover with a keyboard-driven listbox. Built on the Radix Popover already bundled in `radix-ui` — no extra dependency (no cmdk). Scales to hundreds of options where a flat Select does not. The accessible name comes from `aria-labelledby` + the current value.

## Why filterComboboxOptions is a separate pure function

`filterComboboxOptions` (`combobox-filter.ts`) is shared by `Combobox` and unit-tested directly (jsdom-safe — no Radix/portal rendering needed).

It does a case-insensitive AND match: every whitespace-separated term must appear in `label + keywords`, caching the lowercased search haystack per `ComboboxOption` in a `WeakMap` so repeated keystrokes do not re-allocate or lowercase unchanged options. An empty or whitespace-only query returns every option with order preserved.

## WAI-ARIA combobox pattern and keyboard parity

The custom combobox maintains parity with Radix Select by tracking keyboard navigation and ARIA attributes across trigger and listbox.

Opening the popover (via click, Space, Enter, ArrowDown, or ArrowUp on the closed trigger) resets any prior search query and initializes the highlighted item to the currently selected enabled option rather than always starting from the top, allowing keyboard users to see and navigate relative to their current selection without re-mounting filtered-out rows during popover close animations. The active navigation loop (`moveActive`) skips disabled options in both directions so disabled choices cannot be reached via ArrowDown or ArrowUp keys, and `clampedActive` falls back to the first enabled option if the active item becomes disabled while the popover is open.

The trigger exposes `role="combobox"`, `aria-expanded`, `aria-controls`, and forwards `aria-label`, `aria-invalid`, and `aria-describedby` from form fields. The search input carries `data-slot="combobox-input"` and `aria-autocomplete="list"`. Options carry `role="option"`, `aria-selected`, `aria-disabled`, and sync `data-highlighted` with the search input's `aria-activedescendant` attribute for consistent screen reader and visual cues.

