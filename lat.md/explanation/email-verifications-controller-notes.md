---
lat:
  mode: explanation
---

# Users::EmailVerificationsController design notes

This controller captures and verifies the email address a user must have before they can email their legislators (`User#email_sendable?`).

## Why the pending address lives only in the session

The address is held in `session[:pending_email]` until the code is approved, so a mistyped address never lands on the user row.

The approval write (`#update`) uses `update!` with a rescue, so a duplicate email hits the unique index and comes back as an Inertia error rather than failing silently.

A bearer client is identified by its `Authorization` header, not by the cookie. [[app/controllers/application_controller.rb#ApplicationController#authenticated_bearer_request?]] lets such a request skip forgery protection, and [[app/controllers/application_controller.rb#ApplicationController#current_user]] resolves the account from the API key. The rules are in [[identity-and-access#Sessions, cookies and bearer tokens]]. The cookie therefore matters to a bearer client for one thing only: carrying `pending_email` from `#create` to `#update`.

The session is Rails' default cookie-store session, with no custom session store configured. `#create` answers a bearer request with a `Set-Cookie` for the session key (path `/`, HttpOnly, SameSite=Lax). `#update` finds `pending_email` only when that cookie comes back on the next request. When the cookie is missing, `#update` answers 422 with the `email_verification_failed` error envelope, the detail "Start over and re-enter your email address.", and no Twilio check.

[[spec/requests/users/email_verifications_bearer_session_spec.rb]] pins both outcomes with a real cookie jar and forgery protection switched on: the replayed cookie verifies the address, and a cookie dropped between the two steps, like a call with no earlier `#create`, ends in the start-over failure. The older `Users::EmailVerifications` request spec stubs the session. That stub keeps `pending_email` whether or not a cookie returns, so it cannot tell the two outcomes apart.

Whether React Native's networking stack stores the `Set-Cookie` from `#create` and sends it with `#update` has not been run on an iOS simulator or device, nor on an Android emulator or device. The server side is established. The client side is unverified on both platforms.

## Why destroy also clears a stale unverified email

`#destroy` ("Start Over") drops the pending session address.

It also clears an unverified `user.email` left over from an old controller (which used to write `email` before verification), so the client flow returns cleanly to the email-entry step rather than showing a half-verified address.

## Why respond_failure supports both response formats

Web gets a redirect with Inertia errors (the modal reads `form.errors`).

Mobile gets the structured JSON error envelope — no mobile email UI exists yet, but the endpoint answers both formats like the rest of the internal endpoints, so it is ready when one is built.

## Why the redirect target carries with: "legislator,address"

The verification steps live in a modal on the bill page.

The verification steps live in a modal on the bill page; `bill_target`'s `with:` param keeps the legislator/address partial props present after the redirect (`BillsController#show` honors `params[:with]`), so the modal's surrounding page doesn't lose that context on redirect.

`bill_target` also checks the top-level `params[:bill_id]` in addition to the nested one: Rails' params wrapping does not wrap DELETE bodies the way it does POST/PATCH, so `#destroy`'s bill id can arrive outside the `email_verification` key.

## Why email_verification_params uses fetch, not require

`params.fetch(:email_verification, {})` rather than `params.require(...)`, because `#destroy` can legitimately arrive with no payload beyond the (optional) bill id — requiring the key would raise on a valid, empty request.

## Frontend: EmailLegislatorsModal.tsx

The current "email your representatives" flow was rebuilt on today's design system from the older four-step form.

Which step to show is worked out from the user's own data: enter an email, enter the code, send the message. Only the move from the email step to the code step is held in this component, because the address being verified lives on the server, in the session, and is deliberately not written onto the user's record until the code is approved.

Once the code is approved, the redirect brings back a fresh copy of the user, `isVerified` turns true, and the send step appears by itself — nothing has to be recorded in the component for that transition.

The redirect from a successful send carries a flash message ("Sending emails... You will be CC'ed on them."), which `registerFlashToasts` turns into a toast by itself.

The send step's error read is widened because the server can refuse the send with an `email` error, when the verification has lapsed — that key is not part of `sendForm`'s own data, which is why `(sendForm.errors as Record<string, string | undefined>).email` is read through a wider type than the form's own `errors`.

## Twilio error handling

The rescue in `#update` follows the same pattern as elsewhere in the app: see [[docs/explanation/twilio-error-phone-redaction.md|twilio-error-phone-redaction.md]] for why only safe numeric fields are captured inside the rescue and the sanitized error is raised outside it.
