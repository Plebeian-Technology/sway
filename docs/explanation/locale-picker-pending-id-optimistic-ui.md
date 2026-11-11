---
mode: explanation
summary: "Why useLocale tracks a pending locale id in local state instead of binding a locale picker directly to server-confirmed state."
status: agent-extracted
related: [docs/reference/use-locale-hook-contract.md]
---

# Why useLocale tracks a pending locale id

`useLocale` (`app/frontend/hooks/useLocales.ts`) holds the locale the
reader has chosen but the server hasn't confirmed yet, separately from the
confirmed `sway_locale` value.

A `<select>` bound directly to the active locale is bound to SERVER state.
React resets a controlled input's displayed value as soon as the change
event finishes handling, so picking a new jurisdiction would show the new
label for a moment, then snap the control back to the old one, where it
would sit until the server's response arrived. Measured at 1.6 seconds
against a deliberately slowed-down test server — and on a slow connection,
that reads as though the choice never registered at all.

Holding onto the pending id keeps the control showing what the reader
actually picked for the whole round trip, resolving as
`pendingLocaleId ?? locale?.id` at every call site (see
`docs/reference/use-locale-hook-contract.md` for the full return contract).
