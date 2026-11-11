---
lat:
  mode: explanation
---

# Why PositionCard reads props at Edit-click time, not at mount

The edit fields on a `PositionCard` must be filled from the props as they are at the moment Edit is clicked, not from the props the card first saw.

A partial reload can change `position.support` and `position.summary` while the card stays on screen. Filling the fields only once, at the start, meant a later Save quietly wrote old values over newer data from the server.
