---
lat:
  mode: explanation
---

# Why diffToTailwind.ts uses a plain colour wash

Shows what changed between two strings, one character at a time, in the v2 UI.

It takes what `diff.diffChars` returns and tints each piece with a Tailwind background colour: `bg-success/20` for text that was added, `bg-destructive/20` for text that was removed. A plain colour wash is the look the user chose: no strikethrough, no underline, no inline styles.
