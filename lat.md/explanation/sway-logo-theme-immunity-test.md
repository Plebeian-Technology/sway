---
lat:
  mode: explanation
---

# Why SwayLogo.test.tsx guards against theming

The Sway logo is one fixed picture file (`public/images/sway-us-light.png`) that works on any background — it sits OUTSIDE the theme system, and no theme recolors or restyles it.

These tests stop `SwayLogo` from turning into something a theme can paint: an inline SVG with `fill="currentColor"`, or a component reaching for `--primary`, `bg-*`, `rounded-*`, or other theme classes.
