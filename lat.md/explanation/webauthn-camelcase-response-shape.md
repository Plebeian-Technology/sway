---
lat:
  mode: explanation
---

# Why mobile WebAuthn responses keep the spec's camelCase shape

`Api::V1::RegistrationsController#create` and `Api::V1::SessionsController`'s challenge endpoints return `webauthn-ruby`'s `as_json` output for `PublicKeyCredentialCreationOptions` / `PublicKeyCredentialRequestOptions` unchanged.

`Api::V1::RegistrationsController#create` and `Api::V1::SessionsController`'s challenge endpoints return `webauthn-ruby`'s `as_json` output for `PublicKeyCredentialCreationOptions` / `PublicKeyCredentialRequestOptions` unchanged — camelCase, with a nested `rp`, `pubKeyCredParams`, and (for sign-in) `allowCredentials`/`rpId`.

`react-native-passkey`'s `PasskeyCreateRequest` and `PasskeyGetRequest` require this exact WebAuthn-spec shape. An earlier version of these endpoints returned the older flat snake_case payload instead. On iOS that made the passkey ceremony fail with the uninformative "An unknown error occurred," rather than a clear parsing error — the native library expects the spec shape and does not validate or report a mismatch, so the failure mode looks like an unrelated bug.
