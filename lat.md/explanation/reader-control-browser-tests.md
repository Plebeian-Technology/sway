---
lat:
  require-code-mention: true
---
# Reader control browser tests

Browser examples prove that public navigation and reader controls change the server-rendered experience.

These scenarios fill distinct gaps beside [[bill-categories-spec#The bill categories browser spec#What it leaves to other tests]], [[low-friction-voting#Low-friction voting#Provisional vote capture and cookie lifecycle]], and [[theme-tokens#Theme tokens#Why the active theme is watched rather than passed down]]. They exercise browser controls and server-produced results, including the cookie-backed provisional choice.

## Guest preview

An unsigned reader follows Preview Sway into the monthly bill and submits a provisional choice.

### Guest Preview Sway reaches provisional voting

The successful registration prompt and refreshed banner gate checks that no user, vote, or official score was written. The web preview destination is owned by [[low-friction-voting#Low-friction voting#Web and mobile preview destinations]].

## Bills locale selection

The public bill list uses the selected jurisdiction to choose which bills appear.

### The bills picker switches the visible list between locales

Selecting another native locale option replaces the visible bill list with that jurisdiction's bill and removes the prior jurisdiction's bill.

## Theme selection

The theme picker changes the browser's active theme and the server-provided theme for later navigation.

### The rendered theme picker changes and persists the theme

Selecting a visible alternative in the drawer changes the root theme attribute, and a later server-rendered page keeps the selected theme.
