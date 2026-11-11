---
lat:
  mode: explanation
---

# Asserting across a save-and-reload without a stale element reference

`spec/system/organization_follows_spec.rb`'s "round-trips the org-notification master toggle" example checks two things in one assertion.

`spec/system/organization_follows_spec.rb`'s "round-trips the org-notification master toggle" example checks two things in one assertion: that the save leaves the operator on the tab they were working in, and that the badge there shows the saved state.

That single assertion could not always do both. `#update_org_defaults` used to redirect to a bare `/notifications`, which drops `?tab=` and unmounts the whole Organizations panel, landing the operator on Push instead. The old gate never caught that, because it read a badge drawn from client-side form state and passed on the value as it stood BEFORE the redirect.

Fixing the redirect to keep `?tab=` alive is only half of it — the assertion also has to survive being run against a page that gets torn down and rebuilt mid-check. `find` hands back ONE element, and the reload that follows the save throws that element away and builds a new one; reading text off the old one then fails with "stale element reference," which reads like the badge said the wrong thing. `have_css` asks again on every retry, so a rebuilt badge is simply found again instead of raising on the DOM churn.

## Why the push-subscription redirects also needed to name their tab explicitly

`Notifications::PushNotificationSubscriptionsController`'s four redirects (subscribe/unsubscribe, enable/disable) were left naming no tab at all, the same defect `NotificationsController`'s two saves were fixed for above.

Nothing had misbehaved in practice, and the reason was luck: `Notifications.tsx` falls back to the Push tab when the browser supports push, which is the only condition under which subscribing or unsubscribing can run at all — so the untested fallback happened to always land the operator back where they started. Change that fallback and all four redirects start dropping the operator somewhere else with nothing to catch it. These four redirects now name their tab explicitly too, making the destination something the server states rather than something the client happens to guess right.

## Why every NotificationsController redirect names its tab explicitly

The open tab on the Notifications screen lives in the URL as `?tab=<value>`, which `Notifications.tsx` reads on every render.

The open tab on the Notifications screen lives in the URL as `?tab=<value>`, which `Notifications.tsx` reads on every render — a redirect that drops it doesn't just lose a highlight, it unmounts the panel the operator was working in and lands them on Push. Values must match the `TabValue` union in `app/frontend/pages/Notifications.tsx` (`"push"`, `"sms"`, `"organizations"`); an out-of-union value silently falls back to the default tab.

`NotificationsController::PUSH_TAB` is unused by that controller itself — it exists so the push subscription controller (this screen's other half) shares one constant instead of a second copy of the string that could drift. A bare redirect only happens to land on Push today because that's `Notifications.tsx`'s own fallback; that's not guaranteed, so every redirect still names its tab explicitly rather than relying on it.

A failure redirect carries its tab too, for the same reason: errors shown on a tab whose form is not on screen are errors nobody can act on.
