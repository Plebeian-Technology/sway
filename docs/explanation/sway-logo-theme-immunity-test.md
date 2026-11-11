---
mode: explanation
summary: "Why SwayLogo.test.tsx guards the logo staying a fixed image file outside the theme system, rather than an inline SVG a theme could recolor."
status: agent-extracted
related: []
---

# Why `SwayLogo.test.tsx` guards against theming

The Sway logo is one fixed picture file
(`public/images/sway-us-light.png`) that works on any background — it
sits OUTSIDE the theme system, and no theme recolors or restyles it.

These tests stop `SwayLogo` from turning into something a theme can
paint: an inline SVG with `fill="currentColor"`, or a component reaching
for `--primary`, `bg-*`, `rounded-*`, or other theme classes.
