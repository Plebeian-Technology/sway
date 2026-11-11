---
mode: explanation
summary: "Why the ui/Combobox primitive is built on Radix Popover instead of cmdk, and why its option filter is a separately unit-tested pure function."
status: agent-extracted
related: [docs/explanation/bill-creator-picker-mechanics.md]
---

# `ui/Combobox` primitive design

Searchable single-select combobox. A trigger button shows the current
selection; opening it reveals a type-to-filter Popover with a
keyboard-driven listbox. Built on the Radix Popover already bundled in
`radix-ui` — no extra dependency (no cmdk). Scales to hundreds of options
where a flat Select does not. The accessible name comes from
`aria-labelledby` + the current value.

## Why `filterComboboxOptions` is a separate pure function

`filterComboboxOptions` (`combobox-filter.ts`) is shared by `Combobox`
and unit-tested directly (jsdom-safe — no Radix/portal rendering needed).
It does a case-insensitive AND match: every whitespace-separated term
must appear in `label + keywords`. An empty or whitespace-only query
returns every option with order preserved.
