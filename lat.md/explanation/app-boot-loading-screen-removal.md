---
lat:
  mode: explanation
---

# Why App.tsx deletes the loading screen with useLayoutEffect

`App.tsx` deletes the loading screen the server sent, now that React has mounted.

That screen's div has `display: flex` written directly on the element (the ERB layout does that so it looks right on the very first paint, before `application.css` has loaded). A stylesheet rule cannot override a style written on the element itself, so the only way to hide it is to remove the div. `useLayoutEffect` runs before the browser paints, so the 80vh-tall loading screen is gone before anyone sees the real app.
