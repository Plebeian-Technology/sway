---
lat:
  mode: explanation
---

# Why isSafeExternalHref exists

A shared check for any screen that builds an `<a href={...}>` out of a value an admin typed in, or any other value we do not fully trust.

Why it exists: an admin-supplied tool path could otherwise put a `javascript:` URL into the page. Inertia intercepts a plain left click, but a middle click, a Ctrl-click or "Open in new tab" goes straight to the browser and would run it. The admin index page needed this first; `Drawer.tsx`'s external-link branch, and anything added later, calls the same code instead of copying the logic.

Empty values are rejected on purpose: `new URL(null, origin)` does NOT throw — it turns `null` into the text `"null"` and hands back a valid https URL.

Returns true only when `path` is a non-empty string that resolves to an `http:` or `https:` URL. Everything else returns false: `javascript:`, `data:`, `mailto:`, well-formed URLs with other schemes, and junk strings that make `URL` throw.

`isSafeExternalHref` moved to `app/frontend/sway_utils/safeHref.ts` (it used to live in `admin/Index.tsx`) so `Drawer.tsx`'s external-link branch, and any future caller, can use the same guard without duplicating the logic.

Alongside `isSafeExternalHref`, `isSafeUrl` provides strict validation for external citations and reporting links, requiring an explicit `http:` or `https:` scheme, a valid non-empty hostname, and rejecting embedded user credentials or dangerous protocols like `file:` and `javascript:`.
