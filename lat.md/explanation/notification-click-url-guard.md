---
lat:
  mode: explanation
---

# Why the notification-click URL guard is its own function

The notification-click handler runs inside the service worker, where a test cannot watch it, so these tests check the URL guard that was pulled out of it.

The rule: for a link on our own site, hand back its path and query string; for anything missing, broken, or pointing at another site, hand back "/".
