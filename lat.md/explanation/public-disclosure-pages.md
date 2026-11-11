---
lat:
  mode: explanation
---

# Public disclosure pages

`/sms`, `/privacy` and `/terms` render without authentication so a carrier reviewer, an App Store reviewer, or a crawler can read them with no Sway account and no session.

## Why the carrier reviewer needs a page with no account

A Twilio A2P 10DLC reviewer has no Sway account and has no reason to create one just to verify an SMS opt-in screen.

The real consent checkbox lives on `/notifications`, behind `authenticate_sway_user!`. Gating a disclosure page behind SMS verification would not help either: verifying a phone number means sending it a text, which is the very capability under review. `/sms` breaks that circularity — a reviewer reaches it with no login and no phone verification, the same way `/download` is reachable for an App Store reviewer with no account.

## Why the component tests are the only cover for the text

Server-side rendering is off, so a request spec sees the Inertia shell rather
than the words on these pages.

That leaves each page's own component test as the only thing asserting the
disclosure text a reviewer reads — the SMS call-to-action, the terms, and the
privacy policy's mandatory "never sold" clause. A page whose copy is the reason
it exists is therefore covered where the copy is rendered, not where the route
is served.

The entrypoint that mounts them is deliberately minimal: it pulls in none of
the authenticated bundle — no service worker registration, no Active Storage,
no scroll-restoration polyfill, no flash toasts, no authenticated layouts —
because a reviewer with no account should not be shipped the signed-in
application to read a policy.

## Why /sms renders the live consent panel instead of a screenshot

A reviewer must see the consent screen as signed-in users see it, and a static screenshot drifts from the live page and can leak the sending number into the repository.

`/sms` therefore renders [[app/frontend/components/notifications/SmsNotificationsPanelView.tsx]], the same view the `/notifications` SMS tab draws through [[app/frontend/components/notifications/SmsNotificationsPanel.tsx]], in its preview mode. The panel keeps the form state and the save request; the view only draws. Preview mode disables the checkbox and the save button and never submits, so the public page needs no session, no form request and no live connection. The label and disclosure come from `SMS_CONSENT_LABEL` and `SMS_CONSENT_DISCLOSURE` (`app/frontend/sway_constants/smsConsent.ts`), so the preview cannot drift from what Sway submitted to Twilio.

The page carries no second, hand-built copy of the checkbox. The preview already holds the checkbox, label and disclosure, and two checkboxes with one accessible name confuse a screen-reader user.

The sending number reaches the page as the `sms_phone` prop, formatted by [[app/services/sway/twilio_client.rb#TwilioClient#display_from_phone|display_from_phone]] — the source [[sms-notification-service-design#Where the displayed Sway number comes from]] describes. The page states "Messages come from" that number above the program description, and leaves the line out when the number is unset, as the panel does.
