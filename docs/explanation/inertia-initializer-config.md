---
mode: explanation
summary: "Why Inertia's version is the frontend build's fingerprint, and why page history is encrypted in the browser."
status: agent-extracted
related: []
---

<!-- vale Vale.Spelling = NO -->

# Why `config/initializers/inertia.rb` sets `version` and `encrypt_history`

## `config.version`: the frontend build's fingerprint

Inertia sends the version with every response and forces a full page load
when it changes, so a browser holding the old JavaScript cannot keep talking
to a new deploy. In development there is no build to fingerprint, so this is
a fixed string and the version never changes — the Vite dev server replaces
changed modules instead.

## `config.encrypt_history`: why page data is encrypted before it's stored

Inertia keeps a copy of each page's data in history so the Back button is
instant. In a signed-in app that means earlier private screens (vote
history, home address, Bill of the Week answers) would sit in the browser's
history as readable text until the history is cleared. Encrypting them makes
that copy useless to a browser extension or any other code that can reach
the page. Signing out clears the history (see
`Users::Webauthn::SessionsController#destroy`) so the encrypted copies go
away too.
