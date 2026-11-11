---
lat:
  mode: explanation
---

# Why the SMS consent copy is frozen and shared

`SMS_CONSENT_LABEL` and `SMS_CONSENT_DISCLOSURE` are exported constants shared between the notifications panel and the public disclosure page to ensure copy remains identical across surfaces.

Both surfaces that show the copy import them: the notifications panel (`app/frontend/components/notifications/SmsNotificationsPanel.tsx`) and the public `/sms` page (`app/frontend/pages/public/Sms.tsx`), which also uses `SMS_CONSENT_LABEL` inside the prose describing opt-in steps.

## Why the exact bytes matter

Carrier campaigns submitted to The Campaign Registry require an exact match with the live opt-in screen, so any discrepancy risks rejection.

Sending notification text messages from Sway requires an approved Twilio A2P 10DLC campaign. Registration submits the consent wording to The Campaign Registry, and a carrier reviewer compares what was submitted against the live opt-in screen.

## Why the constants are shared rather than duplicated

Exporting shared constants guarantees that the authenticated settings panel and the public review page display identical wording without risk of manual divergence.

The notifications panel is the real opt-in, behind sign-in. The public `/sms` page reproduces it so a carrier reviewer can verify the call to action without creating an account.

The tests are the deliberate exception. `app/frontend/__tests__/SmsNotificationsPanel.test.tsx` and `app/frontend/pages/__tests__/PublicSms.test.tsx` hard-code the literal strings instead of importing the constants so changes trigger explicit test failures.

## Why a checkbox and not a toggle

Carriers mandate an explicit, unchecked-by-default agreement control, which is provided by a Radix-backed checkbox rather than a preference toggle.

Carriers require consent to be an explicit control that is unchecked by default. A toggle switch expresses a preference, not agreement.
