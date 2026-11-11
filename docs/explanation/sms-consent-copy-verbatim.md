---
mode: explanation
summary: "Explains why the SMS consent label and disclosure paragraph are frozen constants shared between the notifications panel and the public /sms page, and why their exact bytes matter."
status: authored
related: [docs/explanation/sms-notification-service-design.md, docs/explanation/deploy-credential-delivery-gap.md]
---
<!-- vale Vale.Spelling = NO -->

# Why the SMS consent copy is frozen and shared

`SMS_CONSENT_LABEL` and `SMS_CONSENT_DISCLOSURE` live in
`app/frontend/sway_constants/smsConsent.ts`. Both surfaces that show the
copy import them: the notifications panel
(`app/frontend/components/notifications/SmsNotificationsPanel.tsx`) and
the public `/sms` page (`app/frontend/pages/public/Sms.tsx`), which also
uses `SMS_CONSENT_LABEL` inside the prose describing the opt-in steps
rather than repeating the sentence there.

## Why the exact bytes matter

Sending any notification text message from Sway requires an approved
Twilio A2P 10DLC campaign. Registration submits the consent
wording to The Campaign Registry, and a carrier reviewer compares what
was submitted against the live opt-in screen. Copy that differs between
the submission and the product is grounds for rejection on its own.

Sway's first submission was rejected in part for exactly this class of
mismatch: the registration described users checking a box agreeing to
receive text messages, while the product shipped a toggle switch with no
consent language at all.

So these two strings are not ordinary UI copy. Rewording either one
invalidates an approved campaign until the registration is updated to
match. That includes changes that read as harmless: closing the gap in
`Msg&data`, adding a trailing period, or softening the phrasing.

## Why the constants are shared rather than duplicated

Two surfaces must show identical wording. The notifications panel is the
real opt-in, behind sign-in. The public `/sms` page reproduces it so a
carrier reviewer can verify the call to action without creating an
account, which the reviewer will not do.

Hand-typing the same sentence in two files guarantees eventual drift,
and the drift would be invisible in review — two long sentences that
differ by one character read as identical. One exported constant makes
divergence impossible.

The tests are the deliberate exception.
`app/frontend/__tests__/SmsNotificationsPanel.test.tsx` and
`app/frontend/pages/__tests__/PublicSms.test.tsx` both hard-code the
literal strings instead of importing the constants. A test that imports
the value it is checking passes no matter what that value becomes, which
is worthless for copy whose exact bytes are the requirement. Hard-coding
turns those tests into a tripwire: editing the constant fails them, and
the failure is the reminder that an approved campaign registration now
disagrees with the product.

## Why a checkbox and not a toggle

Carriers require consent to be an explicit control that is unchecked by
default. A toggle switch expresses a preference, not agreement. The
control is the vendored shadcn `Checkbox`, which is Radix-based and
renders `role=checkbox`; `spec/system/notification_delivery_spec.rb`
pins that role deliberately, because "the consent control is a checkbox"
is the compliance requirement rather than an implementation detail.
