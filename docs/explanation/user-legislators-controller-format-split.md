---
mode: explanation
summary: "Why UserLegislatorsController#create branches on format instead of always redirecting -- a JSON caller following an HTML redirect lost its session and appeared signed out."
status: agent-extracted
related: [docs/explanation/serializer-whitelist-endpoints.md]
---

<!-- vale Vale.Spelling = NO -->

# Why `UserLegislatorsController#create` splits its response by format

JSON callers (the mobile app) get the updated legislator list in the
response body. HTML callers (web) follow the redirect to `/legislators`
with a flash message. Without this branch, a JSON caller would follow an
HTML redirect instead, the second request would lose its session, and the
user would appear to be signed out after tapping "Search again".
