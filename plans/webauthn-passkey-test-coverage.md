# Plan: WebAuthn/Passkey Test Coverage

## Context

The entire passkey authentication flow — registration, sign-in, and phone verification — has zero automated test coverage. We just made two backend changes (removing `attr_accessor :webauthn_id`, adding `exclude:` credentials) that ship without any safety net. This plan adds request specs for all three controllers and a model spec for Passkey.

## New Files (7 total)

### 1. `spec/factories/passkey.rb` — Passkey factory

### 2. `spec/support/webauthn_double.rb` — WebAuthn shared context

### 3. `spec/support/twilio_double.rb` — Twilio shared context

### 4. `spec/models/passkey_spec.rb` — Passkey model validations

### 5. `spec/requests/phone_verification_spec.rb` — Phone verification endpoints

### 6. `spec/requests/users/webauthn/registration_spec.rb` — Passkey registration

### 7. `spec/requests/users/webauthn/sessions_spec.rb` — Passkey authentication

## Implementation Order & Details

### Step 1: Passkey Factory (`spec/factories/passkey.rb`)

Simple factory: `user` association, `external_id` (SecureRandom.uuid), `public_key` (SecureRandom.hex), `label` ("Test Passkey"), `sign_count` (0).

### Step 2: Fix SessionDouble — add `dig` support

The existing `spec/support/session_double.rb` does NOT stub `dig`, but all three WebAuthn controllers use `session.dig(:current_registration, "challenge")` etc. Add:

```ruby
allow(session_double).to receive(:dig) do |*keys|
    keys.reduce(session_hash) { |h, k| h.is_a?(Hash) ? h[k] : nil }
end
```

### Step 3: WebAuthn Shared Context (`spec/support/webauthn_double.rb`)

**Purpose:** Stub `WebAuthn::RelyingParty` methods and handle `sign_in` side effects.

**Provides:**

- `fake_challenge`, `fake_credential_id`, `fake_public_key` — deterministic test values
- `registration_options_double` — responds to `.challenge`, `.to_json`
- `authentication_options_double` — responds to `.challenge`, `.to_json`
- `verified_registration_double` — responds to `.id`, `.public_key`, `.sign_count`

**Before block stubs:**

- `WebAuthn::RelyingParty#options_for_registration` → returns `registration_options_double`
- `WebAuthn::RelyingParty#verify_registration` → returns `verified_registration_double`
- `WebAuthn::RelyingParty#options_for_authentication` → returns `authentication_options_double`
- `WebAuthn::RelyingParty#verify_authentication` → yields mock credential, calls block to find stored passkey, returns `[mock, stored]`
- `ApplicationController#reset_session` → delegates to `session_hash.clear` (prevents conflict with SessionDouble)
- `RefreshToken.for` → returns double with `as_cookie` returning a hash (needed by `sign_in`)

### Step 4: Twilio Shared Context (`spec/support/twilio_double.rb`)

**Purpose:** Stub the Twilio REST client chain.

**Provides:**

- `twilio_verification_result` — double responding to `.status` (default: `"approved"`)
- Stubs `Twilio::REST::Client.new` → returns chained double for:
    - `.verify.v2.services(anything).verifications.create(...)` → returns truthy object
    - `.verify.v2.services(anything).verification_checks.create(...)` → returns `twilio_verification_result`

### Step 5: Passkey Model Spec (`spec/models/passkey_spec.rb`)

| Test                        | What it verifies              |
| --------------------------- | ----------------------------- |
| valid with all attributes   | factory produces valid record |
| invalid without external_id | presence validation           |
| invalid without public_key  | presence validation           |
| invalid without label       | presence validation           |
| invalid without sign_count  | presence validation           |
| duplicate external_id       | uniqueness validation         |
| negative sign_count         | numericality ≥ 0              |
| sign_count > 2^32-1         | numericality ≤ 4294967295     |
| belongs_to user             | association                   |

### Step 6: Phone Verification Spec (`spec/requests/phone_verification_spec.rb`)

Includes: `SessionDouble`, `TwilioDouble`

**POST /phone_verification (create)**

- `SKIP_PHONE_VERIFICATION` set → sets `session[:phone]`, returns `{success: true}` 200
- Normal → calls Twilio verify API, returns success based on result
- Twilio error → returns `{success: false}`

**PATCH /phone_verification/:id (update)**

- Approved → sets `session[:verified_phone]`, returns `{success: true}`
- Not approved → does NOT set `session[:verified_phone]`, returns `{success: false}`
- Twilio 20404 error → redirects to root with flash alert
- Other Twilio error → re-raises
- Does NOT create a user (race condition security)

### Step 7: Registration Spec (`spec/requests/users/webauthn/registration_spec.rb`)

Includes: `SessionDouble`, `WebAuthnDouble`

**POST /users/webauthn/registration (create)**

| Context                                     | Test                                                                              |
| ------------------------------------------- | --------------------------------------------------------------------------------- |
| phone verified, user valid                  | returns JSON with challenge                                                       |
| phone verified, user valid                  | stores challenge + user_attributes in `session[:current_registration]`            |
| phone verified, existing user with passkeys | calls `options_for_registration` with `exclude:` containing existing external_ids |
| phone NOT verified                          | returns 200 `{success: false, message: "...confirm your phone..."}`               |

**POST /users/webauthn/registration/callback**

| Context                | Test                                         |
| ---------------------- | -------------------------------------------- |
| verification succeeds  | creates User                                 |
| verification succeeds  | creates Passkey with correct attributes      |
| verification succeeds  | signs in user (`session[:user_id]` set)      |
| verification succeeds  | returns route to registration page           |
| verification succeeds  | cleans up `session[:current_registration]`   |
| existing user          | updates user, doesn't create duplicate       |
| WebAuthn::Error raised | returns 422 with error message               |
| WebAuthn::Error raised | still cleans up session                      |
| passkey save fails     | returns 422 "Couldn't register your Passkey" |
| passkey save fails     | still cleans up session                      |

### Step 8: Sessions Spec (`spec/requests/users/webauthn/sessions_spec.rb`)

Includes: `SessionDouble`, `WebAuthnDouble`, `TwilioDouble`

**POST /users/webauthn/sessions (create)**

| Context                                        | Test                                                           |
| ---------------------------------------------- | -------------------------------------------------------------- |
| blank phone                                    | redirects to root with error                                   |
| 9-digit phone                                  | redirects to root with error                                   |
| 11-digit phone                                 | redirects to root with error                                   |
| user with passkeys                             | returns JSON authentication options                            |
| user with passkeys                             | stores challenge + phone in `session[:current_authentication]` |
| user without passkeys, SKIP_PHONE_VERIFICATION | sets `session[:phone]`, returns 202                            |
| user without passkeys, normal                  | calls Twilio, returns 202 `{success: true/false}`              |
| no user, phone present                         | triggers phone verification flow                               |

**POST /users/webauthn/sessions/callback**

| Context                                | Test                                         |
| -------------------------------------- | -------------------------------------------- |
| auth succeeds, registration complete   | signs in, routes to legislators              |
| auth succeeds, registration incomplete | routes to registration                       |
| auth succeeds                          | sets `session[:verified_phone]`              |
| auth succeeds                          | updates passkey `sign_count`                 |
| auth succeeds                          | cleans up `session[:current_authentication]` |
| user not found                         | raises error                                 |
| WebAuthn::Error                        | returns 422, cleans up session               |

**DELETE /users/webauthn/sessions/:id (destroy)**

- Signs out (clears session)

### Step 9: Request-spec gap closure (high-value scenarios)

Add the following tests to improve failure-path and security invariant coverage:

**Registration (`spec/requests/users/webauthn/registration_spec.rb`)**

- create: verified phone present but invalid user returns `422` with validation errors and does not set `session[:current_registration]`
- callback: missing/invalid `current_registration` payload (missing `challenge` or `user_attributes`) fails safely and does not create `User`/`Passkey`
- callback: pre-verify DB failure (`update!`/`create!`) behaves predictably and validates cleanup behavior

**Sessions (`spec/requests/users/webauthn/sessions_spec.rb`)**

- create: `allow_credentials` payload contains expected `{ id, type: "public-key" }` entries for all passkeys
- callback: credential lookup succeeds via base64 `raw_id` fallback path
- callback: malformed request (missing `publicKeyCredential`) returns controlled failure behavior
- callback: verified credential that no longer maps to a stored passkey fails gracefully

**Phone verification (`spec/requests/phone_verification_spec.rb`)**

- update: `SKIP_PHONE_VERIFICATION` branch sets `verified_phone` and applies default admin/user/address side effects as expected
- update: assert exact Twilio verification-check args (`to`, `code`)

**Authentication side effects (`registration` and `sessions` request specs)**

- successful sign-in writes refresh-token cookie and preserves session-fixation protections (`reset_session` followed by fresh `session[:user_id]`)

### Step 10: Capybara E2E coverage for passkeys

Use Capybara for end-to-end coverage, with Selenium and Chrome DevTools Virtual Authenticator.

**Primary stack**

- `capybara` + `selenium-webdriver` in JS-enabled feature/system specs
- Virtual authenticator via Chrome DevTools Protocol to exercise real `navigator.credentials.create/get`

**Planned E2E scenarios**

- happy-path registration: verify phone, create passkey, complete callback, land on expected route
- happy-path authentication: existing passkey user signs in and lands on expected route
- negative paths: canceled browser prompt, bad challenge/verification failure, unknown credential

Add these as separate system-spec files so they complement (not replace) request specs.

### Step 11: Supporting testing tools/services (optional hardening)

These improvements are valuable, but not required to complete the core plan deliverable.

### Step 12: Delivery phases

- **P0:** request-spec gap closure, Twilio argument assertions, sign-in side-effect checks
- **P1:** Capybara E2E happy-path registration/authentication with virtual authenticator
- **P2:** Capybara E2E negative paths, branch coverage gates, targeted mutation/security checks

## Completion Status

All steps (1-10) are implemented and green. 69 examples total: 64 unit/request + 5 system E2E. `0 failures, 0 pending`.

## Key Route Helpers (verified)

```
POST   /users/webauthn/registration          → users_webauthn_registration_index_path
POST   /users/webauthn/registration/callback  → callback_users_webauthn_registration_index_path
POST   /users/webauthn/sessions               → users_webauthn_sessions_path
POST   /users/webauthn/sessions/callback      → callback_users_webauthn_sessions_path
DELETE /users/webauthn/sessions/:id           → users_webauthn_session_path(id)
POST   /phone_verification                    → phone_verification_index_path
PATCH  /phone_verification/:id                → phone_verification_path(id)
```

## Key Gotchas

1. **SessionDouble needs `dig`** — controllers use `session.dig` but the existing shared context doesn't stub it.
2. **`sign_in` calls `reset_session`** — must stub on ApplicationController to delegate to `session_hash.clear`, otherwise it conflicts with SessionDouble.
3. **`sign_in` creates RefreshToken** — must stub `RefreshToken.for` to avoid DB/crypto side effects.
4. **Session keys are strings inside nested hashes** — controllers use `session.dig(:current_registration, "user_attributes")` with symbol outer key but string inner keys.
5. **ENV stubbing** — use `around` blocks with `ENV[key] = val` / `ENV.delete(key)` in `ensure` for `SKIP_PHONE_VERIFICATION`.
6. **`route_component` returns JSON** — not an Inertia redirect. Tests should parse JSON and check the `route` field.

## Implementation Status

**Last updated:** 2026-02-26

69 total examples (64 unit/request + 5 system E2E), 0 failures (~7s).

| Step | Deliverable                                         | Status  | Examples                              |
| ---- | --------------------------------------------------- | ------- | ------------------------------------- |
| 1    | `spec/factories/passkey.rb`                         | Done    | —                                     |
| 2    | SessionDouble `dig` fix                             | Done    | Handles symbol/string key interop     |
| 3    | `spec/support/webauthn_double.rb`                   | Done    | Stubs RP, reset_session, RefreshToken |
| 4    | `spec/support/twilio_double.rb`                     | Done    | Full client chain stubbed             |
| 5    | `spec/models/passkey_spec.rb`                       | Done    | 8 examples                            |
| 6    | `spec/requests/phone_verification_spec.rb`          | Done    | 9 examples                            |
| 7    | `spec/requests/users/webauthn/registration_spec.rb` | Done    | 15 examples                           |
| 8    | `spec/requests/users/webauthn/sessions_spec.rb`     | Done    | 17 examples                           |
| 9    | Gap closure (security invariants)                   | Done    | All items covered                     |
| 10   | Capybara E2E                                        | Done    | 5 examples (2 happy + 3 negative)     |

### Quality Notes

**Strengths:**

- Clean test structure — proper shared contexts, `let` blocks, `around` for ENV restoration
- Strong security coverage — session fixation, refresh tokens, session cleanup on all error paths
- Good negative testing — WebAuthn errors, missing payloads, Twilio failures, DB save failures
- Session double's `dig` handles symbol/string key interchangeability correctly
- System specs use Chrome CDP Virtual Authenticator with real `navigator.credentials.create/get`
- E2E negative paths cover canceled prompt, tampered challenge, unknown credential

**Minor concerns:**

- Heavy use of `allow_any_instance_of` — acceptable but could be cleaner with DI
- System test `browser_json_request` bypasses Inertia/React entirely — JSON API test in a browser, not a true UI test

## TODO

### Medium Priority

- [ ] **RefreshToken model spec** (`spec/models/refresh_token_spec.rb`)
  - Source: `app/models/refresh_token.rb`
  - `RefreshToken.for(user, request)` — creates token, destroys existing one first, captures IP + user-agent
  - `#expired?` — checks `expires_at < Time.zone.now` (1-year TTL)
  - `#is_valid?(request)` — compound check: not expired + IP match + user-agent match
  - `#as_cookie` — returns `{ value:, httponly: true, expires:, secure: <production?>, same_site: "Strict" }`
  - Token uniqueness (indexed)
  - Edge case: creating new token while old one exists (should destroy old)

- [ ] **Authentication concern spec** (`spec/controllers/concerns/authentication_spec.rb`)
  - Source: `app/controllers/concerns/authentication.rb`
  - `send_phone_verification(session, phone)` — normalizes phone, calls Twilio Verify `.verifications.create(to:, channel: "sms")`, stores in session, returns boolean; logs + captures to Sentry on error
  - `verified?` — returns `@user&.is_phone_verified`
  - `passkey?` — returns `@user&.passkeys&.size&.> 0`
  - `find_by_phone(phone)` — `User.find_by(phone:)` with memoization via `@find_by_phone`
  - `SKIP_PHONE_VERIFICATION` ENV flag bypasses Twilio call
  - Test via anonymous controller or controller concern testing pattern

- [ ] **User model passkey methods** (`spec/models/user_spec.rb`)
  - Source: `app/models/user.rb`
  - `has_sway_passkey?` — returns `passkeys.size.positive?` (test 0 vs 1+ passkeys)
  - `can_delete_sway_passkeys?` — returns `passkeys.size > CREDENTIAL_MIN_AMOUNT` (min=1, so need 2+ to delete)
  - `webauthn_id` — auto-generated via `after_initialize` callback using `WebAuthn.generate_user_id`; should be set on new records, preserved on existing, unique indexed

- [ ] **WellKnownController spec** (`spec/requests/well_known_spec.rb`)
  - Source: `app/controllers/well_known_controller.rb`
  - `GET /.well-known/webauthn` — returns `{ origins: ["https://sway.vote"] }` only when `request.host == "app.sway.vote"`
  - Test host matching: `app.sway.vote` → JSON response, other hosts → no/empty response
  - Skips authentication (`skip_before_action :authenticate_sway_user!`)

### Low Priority

- [ ] **RelyingParty concern spec** (`spec/controllers/concerns/relying_party_spec.rb`)
  - Source: `app/controllers/concerns/relying_party.rb`
  - `relying_party` returns `WebAuthn::RelyingParty` with:
    - Production: `id: "app.sway.vote"`, `allowed_origins: ["https://app.sway.vote", "https://www.sway.vote", "https://sway.vote"]`
    - Non-production: `id: nil` (uses origin domain), origins from request host
    - `name: "sway-#{ENV["RAILS_ENV"]}"`
    - `credential_options_timeout: 120_000`
  - Test via anonymous controller that includes the concern

- [ ] **Rate limiting specs** — Both `RegistrationController` and `SessionsController` use `rate_limit(to: 100, within: 1.minute)`. Send 101 requests and assert the last returns `429 Too Many Requests`. May need `Rack::Attack` or Rails rate-limiting test helpers depending on how Rails 8.1 implements this.

- [ ] **WebAuthn::FakeClient for request specs** — The `webauthn` gem ships `WebAuthn::FakeClient` (`require "webauthn/fake_client"`) which generates realistic attestation/assertion payloads. Could replace the current `WebAuthnDouble` stubs with a real RP + FakeClient for higher-fidelity request tests:
  ```ruby
  fake_client = WebAuthn::FakeClient.new(origin: "https://localhost:3333")
  credential = fake_client.create(challenge: challenge, rp_id: rp_id)
  # post callback with credential — no stubs needed
  ```
  Main benefit: tests the actual WebAuthn verification code path instead of stubbing it away.

- [ ] **SimpleCov branch coverage gates** — Add branch coverage thresholds for `users/webauthn/*` and `phone_verification*` in `.simplecov` or `spec/rails_helper.rb` to prevent regressions.

- [ ] **Reduce `allow_any_instance_of` usage** — Refactor WebAuthn RP stubs to use dependency injection (e.g., expose `relying_party` as an injectable method, override in tests) for cleaner test setup.

- [ ] **Frontend test infrastructure** — Zero JS test coverage exists. Key files:
  - `app/frontend/hooks/authentication/useWebAuthnRegistration.ts` — `startRegistration`, `verifyRegistration` with AbortController
  - `app/frontend/hooks/authentication/useWebAuthnAuthentication.ts` — `startAuthentication`, `verifyAuthentication` with SMS fallback
  - `app/frontend/sway_utils/webauthn.ts` — `create()`, `get()` wrapping `navigator.credentials`
  - `app/frontend/pages/Passkey.tsx` — login page with passkey-first + SMS fallback flow
  - Needs: Vitest setup, `@testing-library/react`, mock for `navigator.credentials` API

- [ ] **WebMock/VCR + Twilio test credentials** — Replace hand-rolled `TwilioDouble` with recorded HTTP interactions for deterministic payload-shape assertions. Use `webmock` or `vcr` gem to record actual Twilio Verify API responses.

- [ ] **Lightweight security checks in CI** — Add RSpec examples or a Rake task that asserts: auth cookies are `httponly` + `secure` + `SameSite=Strict`, `reset_session` is called before `session[:user_id]=`, and `session.delete(:current_registration/:current_authentication)` is in `ensure` blocks.

## Verification

```bash
# Run unit + request specs
bundle exec rspec spec/models/passkey_spec.rb \
  spec/requests/phone_verification_spec.rb \
  spec/requests/users/webauthn/registration_spec.rb \
  spec/requests/users/webauthn/sessions_spec.rb

# Run system/E2E specs (requires Chrome)
bundle exec rspec spec/system/webauthn_passkey_spec.rb

# Run full suite to check for regressions
bundle exec rspec
```
