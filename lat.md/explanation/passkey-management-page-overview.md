---
lat:
  mode: explanation
---

# Passkey management page overview

`app/frontend/pages/PasskeyManagement.tsx` is the page where a signed-in user manages their registered passkeys.

A passkey is the fingerprint, face, or device PIN this app uses in place of a password.

The list arrives as server props, which is the usual Inertia way. Adding a passkey posts JSON through `useHttp` and then re-fetches just this list, so the user never has to reload the page.

When a passkey is registered, Sway records the authenticator's AAGUID, the id that says what make and model it is. The `device` field is the friendly name looked up from it, or null, which shows as "Unknown device".

## Why the listing has no add/remove buttons of its own

`Users::PasskeysController#index` answers with an Inertia page (cookie/session auth) OR JSON (bearer auth), per the `MobileFormatNegotiation` concern, so mobile gets the same view-only metadata as web.

The listing includes a remove button, protected by the same phone-confirmed window as adding a passkey; lost-passkey recovery goes through support, because Sway's auth model ties one phone to one passkey. The add-a-passkey actions are a separate, SMS-gated flow (see [[docs/explanation/discoverable-passkey-design.md|discoverable-passkey-design.md]]).

## Threats considered

Security boundaries protecting passkey registration and removal against session hijacking, credential replay, and unauthorized deletion.

- **Information disclosure**: the query is scoped to `current_user.passkeys`,
  so a user can only ever see their own.
- **Privilege escalation**: inherits `authenticate_sway_user!` from
  `ApplicationController`, so only signed-in users get in.

## Why this controller is NOT admin-gated

This is a per-user account-management page.

The admin-controller allowlist in `CLAUDE.md` does NOT include `Users::PasskeysController`; it must not gain `verify_is_sway_admin` or be listed in `lib/tasks/sway_lint.rake`'s admin guard check.

## Why label uniqueness is a model validation, not just a DB index

`Passkey` validates `label` uniqueness scoped to `user_id`, on top of the matching `index_passkeys_on_user_id_and_label` database index.

The validation exists so the multi-passkey UI can reject a duplicate device label with a friendly form error, rather than surfacing a raw database uniqueness-violation exception to someone naming their second device the same as their first.

## Browser coverage for both passkey screens

Two sign-in screens shipped with no browser coverage before `spec/system/passkey_management_spec.rb`.

Two sign-in screens shipped with no browser coverage before `spec/system/passkey_management_spec.rb`: the "Add a passkey" flow on `/users/passkeys`, which first sends an SMS code, and the "Sign in with a passkey" button on the login panel. Both run against the browser's real `navigator.credentials` API, backed by the fake authenticator Chrome provides for testing. That fake can store credentials on itself, which is what lets a sign-in succeed without being handed a list of credentials to try.

The spec relies on one account per phone number: adding a credential needs a fresh SMS check, which `TwilioDouble` approves, and passkey sign-in only works for an account that already has a credential tied to its phone.

## Mobile: PasskeyManagementScreen

`PasskeyManagementScreen` (`mobile/src/screens/PasskeyManagementScreen.tsx`) lists the passkeys a user has registered, and lets them add another if they want one.

Adding one goes: confirm the account phone number, enter the SMS code, name the device, then create a passkey the phone can offer on its own next time. The screen used to be view-only, with recovery pointing at support; being fully locked out still means contacting support. Asking for an SMS code again puts a second check on top of the session the user is already in.

The rows sit inside a Card, and the "nothing here" case uses the shared EmptyState. The server only accepts DELETE via the phone-confirmed window; admin/support tooling for passkey management is deprecated.
