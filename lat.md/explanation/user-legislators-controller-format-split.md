---
lat:
  mode: explanation
---

# Why UserLegislatorsController.create splits its response by format

JSON callers (the mobile app) get the updated legislator list in the response body.

HTML callers (web) follow the redirect to `/legislators` with a flash message. Without this branch, a JSON caller would follow an HTML redirect instead, the second request would lose its session, and the user would appear to be signed out after tapping "Search again".

## A failed lookup leaves the links alone

When the representative lookup raises, [[app/controllers/user_legislators_controller.rb#UserLegislatorsController#render_representatives_unavailable]] answers with a handled error instead of a 500.

The caller is already registered and already has representative links, so the request has nothing to complete: the useful outcome is a message to try again and the links the user had before. JSON callers get a 503 with the code `registration_unavailable` and [[app/controllers/user_legislators_controller.rb#UserLegislatorsController#REPRESENTATIVES_UNAVAILABLE_MESSAGE]]; HTML callers return to `/legislators` with that message as the flash alert. The exception is logged and sent to Sentry, so an upstream outage or a bad roster row still surfaces to the operator.
