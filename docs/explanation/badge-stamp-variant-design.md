---
mode: explanation
summary: "Why Badge has solid and stamp variants per the 27.3 UI spec, the Tailwind v4 paren-var ring-width bug it works around, why stamp text uses the tone token instead of a -foreground token, and the matching 27.3-spec look for ui/Tabs."
status: agent-extracted
related: []
---

# `Badge`/`Tabs` 27.3 UI spec design notes

`Badge` has two visual modes per the 27.3 UI spec:

- `variant="solid"` (default, back-compat) — filled pill, legacy badge feel.
- `variant="stamp"` — stamped status: inset 1.5px ring + 12% wash +
  tracked UPPERCASE text.

The `tone` axis colors both variants using the semantic tokens.

## The `ring-[length:...]` vs `ring-(--...)` Tailwind v4 bug

The stamp variant's ring is a 12% wash + 1.5px inset ring + tracked
UPPERCASE text. `ring-[length:var(--neo-border-width)]` sets ring WIDTH;
`ring-(--neo-border-width)` compiles to an invalid ring COLOR with no
width, so the inset ring never renders — the same Tailwind v4 paren-var
bug fixed once before.

## Why stamp text uses the tone token, not a `-foreground` token

A stamp's ground is a 12% wash of its own tone, so the text has to be the
tone itself — the `-foreground` tokens are sized to sit on a SOLID fill
and go invisible on the wash. `info`, `danger` and `primary` already did
this; `success` and `warning` did not.

## `ui/Tabs`: Broadside tabs per the 27.3 UI spec

`ui/tabs.tsx` implements "Broadside tabs" per the 27.3 UI spec:

- full-bleed horizontal strip with a 1.5px bottom rule
- 1.5px vertical rules between triggers
- active state: 3px ink underline + 8% accent wash
- Open Sans 600, UPPERCASE tracking-wide
