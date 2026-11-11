---
lat:
  mode: explanation
---

# Badge/Tabs 27.3 UI spec design notes

`Badge` has two visual modes per the 27.3 UI spec:

- `variant="solid"` (default, back-compat) — filled pill, legacy badge feel.
- `variant="stamp"` — stamped status: inset 1.5px ring + 12% wash +
  tracked UPPERCASE text.

The `tone` axis colors both variants using the semantic tokens.

## The ring-(length:...) vs ring-(--...) Tailwind v4 bug

The stamp variant's ring is a 12% wash + 1.5px inset ring + tracked UPPERCASE text.

`ring-[length:var(--neo-border-width)]` sets ring WIDTH; `ring-(--neo-border-width)` compiles to an invalid ring COLOR with no width, so the inset ring never renders — the same Tailwind v4 paren-var bug fixed once before.

## Why stamp text uses the tone token, not a -foreground token

A stamp's ground is a 12% wash of its own tone, so the text has to be the tone itself — the `-foreground` tokens are sized to sit on a SOLID fill and go invisible on the wash.

`info`, `danger` and `primary` already did this; `success` and `warning` did not. The same rule governs inline warning notices (`bg-warning/12 text-foreground`) and plain-surface warning text (`text-warning`): `--warning-foreground` is white in light mode and near-black in dark mode, so placing it on anything other than a solid `bg-warning` fill renders ~1:1 contrast.

Solid `danger` badges (`bg-destructive`) and `destructive` buttons pair `bg-destructive` with `text-background` rather than `text-white`. The 35-token theme contract has no `--destructive-foreground` token, and `--destructive` shifts from dark red/ink in light mode to light coral, orange, or silver in dark and auto modes, where `--background` is the dark surface guaranteed by `contrast.test.ts` to clear 4.5:1 against `--destructive`.

## ui/Tabs: Broadside tabs per the 27.3 UI spec

`ui/tabs.tsx` implements "Broadside tabs" per the 27.3 UI spec:

- full-bleed horizontal strip with a 1.5px bottom rule
- 1.5px vertical rules between triggers
- active state: 3px ink underline + 8% accent wash
- Typography: Open Sans 600, UPPERCASE tracking-wide
