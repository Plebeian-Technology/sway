---
lat:
  mode: reference
---

# useThemeSync hook

`useThemeSync` (`mobile/src/hooks/useThemeSync.ts`) keeps the light/dark choice held in memory in step with the one saved on the server at `/users/preferences`.

- It hands back a setter that:

1. Changes the app's appearance immediately.
2. Sends `PATCH /users/preferences { preferences: { theme_mode } }` through
   `apiClient`, which adds the login token to the request.
3. Puts the old choice back if that fails, and passes the error on so the
   caller can show a message.

- Changing the look first is what makes the toggle feel instant. The undo step is the safety net for being offline, being signed out, or the server refusing the value.

- The PATCH is sent even when nobody is signed in. The server answers with a redirect or a 401 and `apiClient` turns that into an error. `ThemeToggleScreen` catches it and opens the sign-in sheet.
