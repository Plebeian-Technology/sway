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

[[app/controllers/phone_verification_controller.rb#PhoneVerificationController#update]] applies the same boundary: it logs only the session phone's last four digits and Twilio code, and rebuilds unexpected provider errors from code and status after the rescue block so neither the provider message nor its cause reaches the error reporter (see [[twilio-error-phone-redaction#Why a failed Twilio code check is reported and answered]]). The 20404 browser response is defined by [[identity-and-access#Identity and access#The phone number is the account#A verification-not-found reply has one safe browser outcome]].

[[spec/requests/phone_verification_spec.rb]] checks the XHR and plain 20404 responses, redaction, and unset verified-phone session value; its unexpected-error examples check the fixed reply, the sanitized report, absent cause, and logs. [[spec/system/phone_verification_error_spec.rb]] checks the browser copy, redaction, halted enrollment, and absence of a created user.

## Why SmsDeliveryJob raises DeliveryError outside the rescue block

[[app/jobs/sms_delivery_job.rb#SmsDeliveryJob]] raises [[app/jobs/sms_delivery_job.rb#SmsDeliveryJob#DeliveryError]] after the rescue block completes rather than within it.

Raising an exception inside a `rescue` block causes Ruby to implicitly attach the caught `Twilio::REST::RestError` as the new exception's `.cause`. Standard error loggers traverse nested causes, exposing the raw exception message and its embedded recipient phone number despite the wrapping exception.

Executing the `raise` outside the rescue block ensures `$!` evaluates to nil, decoupling `DeliveryError` from the underlying `RestError`. The job logs only safe numeric error codes before re-raising the unattached `DeliveryError` to trigger Active Job retries with exponential backoff.

## Why send_email_verification doesn't touch the session

Email verification helpers sanitize provider errors while leaving session state management to calling controllers.

`Authentication#send_email_verification` mirrors the sanitized error handling of `send_phone_verification` because SendGrid and Twilio error messages contain recipient addresses. Unlike phone verification, it leaves session state untouched because callers manage `session[:pending_email]` independently.

## Why verification_approved? catches nothing

The verification check helper avoids rescuing exceptions so caller controllers handle specific provider error behaviors.

`Authentication#verification_approved?` provides shared verification logic for `PhoneVerificationController` and `Api::V1::PhoneVerificationsController`. It catches no exceptions because web and mobile controllers implement distinct error flows: the web answers code 20404 ("not found") with a fixed message and every other failure with a reported, fixed reply, while mobile returns false. The method verifies both phone numbers and email addresses.

## Why the TWILIO_FROM_PHONE blank check has a known gap

Blank checks on originating phone numbers detect whitespace-only strings but fail to catch values containing trailing newlines.

`TWILIO_FROM_PHONE` is read outside `Sway::TwilioClient`. While `blank?` checks detect empty or whitespace strings, numbers with trailing newlines pass validation. Twilio rejects such values with `RestError` code 21212, which logs numeric codes without identifying the configuration variable and exhausts job retries.

## Why VotingReminderJob's inner rescue logs only structured fields and the error class

Per-user rescues in voting reminder jobs log structured attributes and error classes to prevent logging raw phone messages.

`VotingReminderJob` wraps `SmsNotificationService.send_voting_reminder` in a per-user rescue block. Because caught errors may contain recipient phone numbers in exception messages, the handler avoids `log_exception` and records only structured attributes and the error class. Full backtraces are logged exclusively in local environments. Outer job rescues safely pass unexpected database or framework errors to standard exception loggers because those failures contain no personal user data.

## Why PhoneVerificationController.update reads e.full_message only to branch

Full exception messages are inspected solely to detect missing verification records and are never logged or re-raised.

In `PhoneVerificationController#update`, `e.full_message` is read exclusively to determine whether Twilio returned a code `20404` verification-not-found error. The message is never logged or attached to re-raised errors because it may contain recipient phone numbers. Only numeric error codes and HTTP status values are logged and packaged into `Authentication::TwilioVerificationError`, which is built and reported after the rescue block completes to prevent Ruby from attaching raw errors as causes.

## Why a Twilio network failure is answered, not raised

A timeout or refused connection to Twilio is an outage, not a bad request, so every SMS endpoint answers it with a handled "try again" reply instead of a 500.

The Twilio client turns a transport failure into `Twilio::REST::TwilioError`, the parent of `Twilio::REST::RestError`. A rescue that names only `RestError` lets it escape. Each SMS endpoint rescues it after its `RestError` rescue: the send helper returns false, the web code check answers a fixed retry message, the mobile endpoints answer 503 `verification_unavailable`, and the add-a-passkey check answers success false.

The mobile code check answers 503 and not 401 `invalid_code`, because the code was never checked and may be right. The web code check returns its fixed message without a report, because an outage needs no stack trace; an unexpected `RestError` is reported first, see [[twilio-error-phone-redaction#Why a failed Twilio code check is reported and answered]].

`TwilioError` carries no code and no status, and its message is the transport library's text, so the logs record only the error class. The send path reports a rebuilt [[app/controllers/concerns/authentication.rb#Authentication#TwilioVerificationError]] naming that class in production, with no cause attached.

[[app/services/sway/twilio_client.rb#TwilioClient#HTTP_TIMEOUT_SECONDS]] bounds every Twilio call, so a stalled connection fails after ten seconds instead of holding the request open for the HTTP adapter's default. The SMS jobs share the client and so share the bound.

## Why a failed Twilio code check is reported and answered

A code check that Twilio refuses for a reason other than "not found" is reported to Sentry and answered with a fixed message, never raised as a 500.

Twilio answers 60200 for a code it cannot parse, 60202 when the check attempts are used up and 20429 when it rate limits the account. [[app/controllers/phone_verification_controller.rb#PhoneVerificationController#update]] answers each with HTTP 200 and `success: false`. Code 60202 says the code can no longer be used and asks for a new one; the others say the code could not be checked.

The controller still reports a [[app/controllers/concerns/authentication.rb#Authentication#TwilioVerificationError]] built from the code and status, in production only, so the failure stays visible. It builds that error after the rescue block ends, so no raw provider error becomes its cause.

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

## Why a missing Verify service id is answered like an outage

A missing `TWILIO_VERIFY_SERVICE_SID` is a configuration fault that sends no SMS, so every SMS endpoint answers it the way it answers a Twilio outage.

Passed a nil id, `services(nil)` raises `ArgumentError` inside the Twilio gem, which no SMS endpoint rescues, so a bad deploy or secret rotation would turn every sign-up into a 500 that does not name its cause. `Authentication#service_sid` instead raises [[app/controllers/concerns/authentication.rb#Authentication#VerifyServiceNotConfiguredError]], a subclass of `Twilio::REST::TwilioError`, so the network-failure rescues in [[twilio-error-phone-redaction#Why a Twilio network failure is answered, not raised]] already catch it at every call site.

The method reports the error to Sentry itself, in every environment, before raising, because most of those rescues do not report. The message names the setting and never a value. The send helper rescues this class ahead of its generic `TwilioError` rescue, so a production send reports the fault once and not twice.

The email verification endpoints share the method but rescue only `RestError`, so a missing service id still raises there, as this named and reported error.
