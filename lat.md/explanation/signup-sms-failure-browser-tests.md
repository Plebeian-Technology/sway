---
lat:
  mode: explanation
  require-code-mention: true
---

# Signup SMS failure browser tests

Browser examples prove that phone verification failure paths and recovery actions display the intended user-facing outcomes.

The signup flow presents a phone entry form followed by a one-time SMS verification code form. The browser tests verify that client-side validation errors, upstream provider transmission failures, verification check errors, and user cancellation preserve form state and provide actionable feedback without stranding the user.

## Short phone number rejection

Phone numbers with fewer than ten digits produce a validation warning toast and keep the user on the phone input step.

When a visitor submits a phone number shorter than ten digits, the client aborts the request, displays a warning notification indicating that ten digits are required, and keeps the phone number input enabled without transitioning to the verification code step.

## Empty confirmation code warning

Submitting a blank confirmation code while on the code step triggers a warning toast and retains the verification code input.

When the confirmation code input is left blank or cleared, attempting to confirm displays a warning notification prompting for the code, while retaining the code entry view and action buttons.

## Upstream error when sending code

A provider rejection during verification creation displays an error toast informing the user and leaves the submit button enabled.

If the upstream SMS provider returns an error response when creating a verification, the server catches the provider error, returns an unverified status, and the browser displays a notification that the code could not be sent.

## Upstream timeout when sending code

A network timeout during verification creation displays an error toast informing the user and keeps the phone step active.

When a network timeout occurs while communicating with the SMS provider, the server handles the error gracefully without raising an unhandled exception, and the browser presents the transmission failure message.

## Daily slot release after failed send

A failed verification send releases its daily rate-limit slot so a retry after the one-minute cooldown succeeds even at the daily threshold.

When Twilio raises an error during verification dispatch, [[app/lib/phone_verification_send_limit.rb#PhoneVerificationSendLimit]] releases that send's slot from the ten-a-day list while keeping the one-minute cooldown active. Pre-consuming nine of the ten daily slots before triggering a failed tenth send proves the retry after waiting out the cooldown completes instead of hitting a daily `429` block.

## Incorrect confirmation code rejection

Submitting a code that the provider does not approve displays an incorrect code error toast and keeps the code input visible.

When the verification check returns an unapproved status, the server reports failure and the browser shows an incorrect code notification while preserving the code input field and submit button.

## Check attempt limit reached

When the provider signals that code verification attempts are exhausted, the page displays a message directing the user to request a new code.

When the SMS provider returns error 60202 indicating that maximum check attempts have been reached, the server maps the error to an instructional message advising the user to request a new code.

## Upstream timeout when checking code

A network timeout during code verification displays an error toast advising retry and preserves the code entry form.

When a timeout occurs during the verification check, the server handles the network failure and returns a retry prompt, keeping the code input interface functional.

## Second verification code request

Requesting another verification code for the same phone number after cancelling succeeds without triggering rate limits.

Because one-time verification codes do not count against per-phone daily SMS limits, a user who cancels and re-enters the same phone number can request a fresh verification code successfully after the send cooldown.

## Cancel confirmation code entry

Clicking cancel from the confirmation code step returns the user to the phone input form with the input field re-enabled.

Choosing to cancel from the code confirmation step resets the form state, clears the code input, and returns to the phone number input screen with the submit button restored.
