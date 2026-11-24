---
lat:
  mode: explanation
---

# Passkey management page overview

`app/frontend/pages/PasskeyManagement.tsx` is the page where a signed-in user manages their registered passkeys.

A passkey is the fingerprint, face, or device PIN this app uses in place of a password.

The list arrives as server props, which is the usual Inertia way. Adding a passkey posts JSON through `useHttp` and then re-fetches just this list, so the user never has to reload the page.

When a passkey is registered, Sway records the authenticator's AAGUID, the id that says what make and model it is. The `device` field is the friendly name looked up from it, or null, which shows as "Unknown device".

## Why the listing answers both web and mobile

`Users::PasskeysController#index` answers with an Inertia page (cookie/session auth) OR JSON (bearer auth), per the `MobileFormatNegotiation` concern, so mobile gets the same metadata as web.

The add-a-passkey actions are a separate, SMS-gated flow (see [[docs/explanation/discoverable-passkey-design.md|discoverable-passkey-design.md]]).

## Removing a passkey

A reader may remove one of their own passkeys on the web, as long as at least one stays.

An earlier design had no remove action at all, on the grounds that one phone ties to one passkey. The operator reversed that so a reader can clean up a lost or retired device without support.

[[app/controllers/users/passkeys_controller.rb#PasskeysController#destroy]] asks for the same evidence as adding one. It runs only inside the phone-confirmed window that `confirm_phone` opens, and it closes that window after a removal, so one SMS check buys one change. A reader who could remove passkeys from an unattended session could otherwise strip a device the owner still uses.

The last passkey stays. The action counts the reader's passkeys and destroys the chosen one inside a single immediate SQLite transaction, so two removals sent at once cannot both see two passkeys and leave none. [[app/models/user.rb#User#MIN_PASSKEY_COUNT]] sets the floor. Refusals answer 200 with `success: false` and a message, the same shape the add flow uses, and the lookup goes through `current_user.passkeys`, so another reader's passkey id answers not found whether or not it exists.

Removal does not change recovery: SMS alone still never opens an existing account, and a reader who loses every passkey still contacts support ([[identity-and-access#The phone number is the account]]).

### The web remove flow

Each passkey row shows a Remove button while the reader has more than one passkey; with one left, the page says it must stay instead.

[[app/frontend/hooks/authentication/useRemovePasskey.ts#useRemovePasskey]] reuses the add flow's `verify_phone` and `confirm_phone` steps to open the window, then asks in the shared confirm dialog, naming the passkey, before it sends the DELETE. The dialog comes after the code because the code is the costly step: a reader who backs out at the dialog leaves an open window rather than a wasted text. A removal refreshes only the `passkeys` prop. A refusal from the server, or a failed request, shows as a toast and leaves the list as it was.

## Threats considered

The listing and removal are scoped to the signed-in reader's own passkeys.

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

The rows sit inside a Card, and the "nothing here" case uses the shared EmptyState. The mobile screen has no remove action.
