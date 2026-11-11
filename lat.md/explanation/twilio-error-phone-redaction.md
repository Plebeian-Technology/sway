---
lat:
  mode: explanation
---

# Twilio error phone redaction

Outbound SMS delivery sanitizes Twilio API errors and suppresses exception cause chains to prevent recipient phone numbers from leaking into application logs and monitoring telemetry.

## Why Twilio error handling redacts recipient identifiers

Twilio API error descriptions embed recipient phone numbers and contact parameters directly within exception messages.

When an API request fails (for instance, with error code 21211 indicating an invalid recipient phone number), the raw `Twilio::REST::RestError#message` string includes the unredacted phone number. Re-raising or passing the raw exception directly would route the recipient's phone number through application logging and external telemetry collectors.

Standard logging infrastructure traverses exception cause chains. Sanitizing the error representation to include only the numeric code and HTTP status code ensures recipient phone numbers are completely stripped before error reporting occurs.

[[app/controllers/phone_verification_controller.rb#PhoneVerificationController#update]] applies the same boundary: it logs only the session phone's last four digits and Twilio code, and rebuilds unexpected provider errors from code and status after the rescue block so neither the provider message nor its cause reaches the error reporter. The 20404 browser response is defined by [[identity-and-access#Identity and access#The phone number is the account#A verification-not-found reply has one safe browser outcome]].

[[spec/requests/phone_verification_spec.rb]] checks the XHR and plain 20404 responses, redaction, and unset verified-phone session value; its unexpected-error example checks the sanitized message, absent cause, and logs. [[spec/system/phone_verification_error_spec.rb]] checks the browser copy, redaction, halted enrollment, and absence of a created user.

## Why SmsDeliveryJob raises DeliveryError outside the rescue block

[[app/jobs/sms_delivery_job.rb#SmsDeliveryJob]] raises [[app/jobs/sms_delivery_job.rb#SmsDeliveryJob#DeliveryError]] after the rescue block completes rather than within it.

Raising an exception inside a `rescue` block causes Ruby to implicitly attach the caught `Twilio::REST::RestError` as the new exception's `.cause`. Standard error loggers traverse nested causes, exposing the raw exception message and its embedded recipient phone number despite the wrapping exception.

Executing the `raise` outside the rescue block ensures `$!` evaluates to nil, decoupling `DeliveryError` from the underlying `RestError`. The job logs only safe numeric error codes before re-raising the unattached `DeliveryError` to trigger Active Job retries with exponential backoff.

## Why send_email_verification doesn't touch the session

Email verification helpers sanitize provider errors while leaving session state management to calling controllers.

`Authentication#send_email_verification` mirrors the sanitized error handling of `send_phone_verification` because SendGrid and Twilio error messages contain recipient addresses. Unlike phone verification, it leaves session state untouched because callers manage `session[:pending_email]` independently.

## Why verification_approved? catches nothing

The verification check helper avoids rescuing exceptions so caller controllers handle specific provider error behaviors.

`Authentication#verification_approved?` provides shared verification logic for `PhoneVerificationController` and `Api::V1::PhoneVerificationsController`. It catches no exceptions because web and mobile controllers implement distinct error flows: the web redirects on code 20404 ("not found") and re-raises other errors, while mobile returns false. The method verifies both phone numbers and email addresses.

## Why the TWILIO_FROM_PHONE blank check has a known gap

Blank checks on originating phone numbers detect whitespace-only strings but fail to catch values containing trailing newlines.

`TWILIO_FROM_PHONE` is read outside `Sway::TwilioClient`. While `blank?` checks detect empty or whitespace strings, numbers with trailing newlines pass validation. Twilio rejects such values with `RestError` code 21212, which logs numeric codes without identifying the configuration variable and exhausts job retries.

## Why VotingReminderJob's inner rescue logs only structured fields and the error class

Per-user rescues in voting reminder jobs log structured attributes and error classes to prevent logging raw phone messages.

`VotingReminderJob` wraps `SmsNotificationService.send_voting_reminder` in a per-user rescue block. Because caught errors may contain recipient phone numbers in exception messages, the handler avoids `log_exception` and records only structured attributes and the error class. Full backtraces are logged exclusively in local environments. Outer job rescues safely pass unexpected database or framework errors to standard exception loggers because those failures contain no personal user data.

## Why PhoneVerificationController.update reads e.full_message only to branch

Full exception messages are inspected solely to detect missing verification records and are never logged or re-raised.

In `PhoneVerificationController#update`, `e.full_message` is read exclusively to determine whether Twilio returned a code `20404` verification-not-found error. The message is never logged or attached to re-raised errors because it may contain recipient phone numbers. Only numeric error codes and HTTP status values are logged and packaged into `Authentication::TwilioVerificationError`, which is raised after the rescue block completes to prevent Ruby from attaching raw errors as causes.

## Why update doesn't create a user on a verified phone

Phone verification actions defer user record creation to prevent pre-registration credential assignment races.

`PhoneVerificationController#update` avoids creating user records upon phone verification. Immediate record creation would introduce a race condition where passkeys could be registered on external devices before legitimate users complete onboarding. Verified numbers are stored temporarily in `session[:verified_phone]`, with user creation occurring later in the registration sequence.

## Why Sway::TwilioClient centralizes the Twilio::REST::Client build

Centralizing Twilio client instantiation consolidates credential handling and preserves existing test stub contracts.

`Sway::TwilioClient` provides a single construction point for `Twilio::REST::Client` instances across `SmsDeliveryJob`, `OnDeactivatedPhoneDeleteUserJob`, and `Authentication#twilio_client`. Centralization ensures existing test stubs continue intercepting client instantiation. Both account credentials are sent via HTTP Basic authentication, so trailing newlines trigger 401 unauthorized errors mimicking expired tokens, as described in [[docs/explanation/env-secret-blank-value-handling.md|env-secret-blank-value-handling.md]].

## Testing that the browser never shows the phone number

System specs verify that failed verification attempts display generic error messages without exposing recipient numbers.

`spec/system/phone_verification_error_spec.rb` verifies that browser interfaces display generic error messages without rendering phone digits in page text when Twilio errors occur. Verification requests execute as background JSON calls, so controller redirects are handled internally while generic error notifications render. Tests construct Twilio error fixtures using `Twilio::REST::RestError.allocate` with stubbed messages to simulate provider error payloads accurately.

## Why the session guard checks for nil, not blank?

Session availability guards test for nil rather than blank state because fresh sessions report empty despite being usable.

`send_phone_verification` verifies `session.nil? || phone_.blank?` rather than invoking `session.blank?`. Brand-new `ActionDispatch::Request::Session` instances report `empty?` as true on initial visits, causing `blank?` checks to misidentify valid sessions as uninitialized.

