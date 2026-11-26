---
lat:
  mode: explanation
---
# Onboarding safety net

Why the onboarding controllers answer an error nobody planned for with a logged, retryable reply instead of a raw 500.

## Why every onboarding endpoint answers an unexpected error

A new user who meets a raw 500 sees a broken page on the web or "HTTP 500" in the app, and nothing says that trying again may work.

The onboarding issues rescue known failures one at a time: Twilio outages, upstream lookups, phone-taken races, a missing service id. Some failures are still unplanned, such as a busy SQLite database or a bug in a collaborator. [[app/controllers/concerns/onboarding_safety_net.rb#OnboardingSafetyNet]] is included by the eight controllers a new user meets: the web and mobile phone verification controllers, the web passkey enrollment and sign-in controllers, the mobile registration controller, the address registration controller, address autocomplete, and the representative links controller.

The net wraps each action in an around callback placed ahead of every other callback, so it also covers a failure in a before callback. It logs the error as `onboarding.unexpected_error`, reports it to Sentry with the controller and action, and answers a JSON or bearer request, and every mobile API request, with 503 and the error code `onboarding_unavailable`. A web request is redirected back, or to the home page, with a flash message that asks the user to try again.

The rescues inside each action run first, because they sit closer to the failure, and keep their own codes and messages. The per-locale rescue in address registration is one of them, so a failing locale is skipped and never reaches the net.

### Errors Rails already answers pass through

The net handles only an error that Rails would answer with a 500, and lets every other error continue unchanged.

Rails maps some exceptions to their own statuses, for example a missing parameter to 400, a missing record to 404 and a bad authenticity token to 422. Some of them also have a handler declared with `rescue_from` on the application or mobile API base controller, which renders the project's own envelope. Those handlers run outside the callback chain, so an error the net re-raises still reaches them. A malformed request is the client's fault and retrying does not help, so turning it into a retryable 503 would mislead.

### A user with a representative link is completed

When address registration fails after the user already has an active representative link, the net completes the registration instead of refusing it.

The link means the representatives were found and saved, so the account is usable; the failing step is something later, such as reconciling a pending vote. The address registration controller overrides the net's reply: it completes the user if needed and gives the normal success reply, JSON 200 with `registration_status: "completed"` or the redirect to the feed. The error is still logged and reported. Only a user with no active link gets the 503 or the retry message.

A change-address save from the web is the exception. A registered reader changing address had active links before the save, so a link proves nothing about this request, and an error before the switch commits would land the reader on the feed with no message, which reads as success. When [[app/controllers/sway_registration_controller.rb#SwayRegistrationController#address_switch_return_path]] picks the change-address page, the net redirects there with the retry message instead ([[web-profile-page#Web profile page#Changing the address from the web]]). Once the switch has committed the new address, the controller notes it and the net answers completed as for any other user with a link, because a retry would be refused by the address-change cooldown.
