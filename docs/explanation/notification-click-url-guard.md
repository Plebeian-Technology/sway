---
mode: explanation
summary: "Why resolveNotificationClickUrl was pulled out of the service worker's notification-click handler as its own testable function, and the rule it enforces for off-site or broken links."
status: agent-extracted
related: [docs/explanation/service-worker-allowed-scope-and-caching.md]
---

# Why the notification-click URL guard is its own function

The notification-click handler runs inside the service worker, where a test
cannot watch it, so these tests check the URL guard that was pulled out of
it. The rule: for a link on our own site, hand back its path and query
string; for anything missing, broken, or pointing at another site, hand back
"/".
