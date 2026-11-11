---
lat:
  mode: explanation
---

# BillCategoryTags.tsx

The subject categories a bill belongs to, drawn as a quiet row of pills.

This is the one place `bill.categories` is shown on the default (Tailwind) screens — the bill detail header and every bill card — so the categories read the same everywhere and match the filter chips on `/bills`.

The names arrive from the server ready to display: `Category#name` is already in Title Case, such as "Budget & Taxes", so nothing is re-capitalised here. A bill with no active categories renders nothing at all, leaving no empty gap or stray label.
