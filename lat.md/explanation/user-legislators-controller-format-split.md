---
lat:
  mode: explanation
---

# Why UserLegislatorsController.create splits its response by format

JSON callers (the mobile app) get the updated legislator list in the response body.

HTML callers (web) follow the redirect to `/legislators` with a flash message. Without this branch, a JSON caller would follow an HTML redirect instead, the second request would lose its session, and the user would appear to be signed out after tapping "Search again".
