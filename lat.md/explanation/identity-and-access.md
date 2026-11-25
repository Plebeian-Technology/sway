---
lat:
  mode: explanation
---
# Identity and access

A Sway account is a phone number with passkeys attached. There is no password anywhere in the system, and the account's real identity — its district, its legislators — is not known until a geocoded address resolves it.

## The phone number is the account

Registration starts with a phone number verified over SMS through Twilio.
Passkeys are then bound to that account, and subsequent sign-ins are WebAuthn.
Email is optional and exists so a user can be reached, not so they can log in.

SMS verifies phone ownership for enrollment, including adding another passkey
or removing one that is not the last
([[passkey-management-page-overview#Removing a passkey]]);
it is not a sign-in or recovery method. A person who loses every passkey needs
support rather than an in-app SMS fallback. The verified phone binding and
unique account constraint are deliberate protections against duplicate accounts.

The consequence is that a deactivated phone number is an account-lifecycle
event rather than a support ticket:
`OnDeactivatedPhoneDeleteUserJob` removes the account. It also means passkey
recovery flows have to reason about a user who has lost every credential but
still controls the number.

Protocol vocabulary stops at the boundary. Sway-owned code says `passkey`;
"WebAuthn" and "credential" appear only where the specification's own words are
required, and `users.webauthn_id` is a documented exception.

### Email is contact data, not an authentication path

Email is optional contact data; phone remains the account identity. Production validation rejects disposable domains and uses a small fallback when its downloaded list is missing.

The nested `EmailValidator` in [[app/models/user.rb]] checks the downloaded blocklist and keeps built-in disposable domains when that file is unavailable.

### First-passkey enrollment

SMS-only enrollment is available while an account has no saved passkey. Once a passkey exists, access requires passkey sign-in; adding another uses the authenticated flow in [[identity-and-access#Identity and access#The admin gate is a lint rule#Adding a passkey re-verifies by SMS first]].

[[app/controllers/users/webauthn/registration_controller.rb#RegistrationController#create|The web enrollment start]] refuses existing-passkey accounts before issuing options. [[app/controllers/users/webauthn/registration_controller.rb#RegistrationController#callback|The callback]] looks up the account again and checks eligibility in the same transaction that saves the user and passkey. SQLite's immediate transaction mode in [[config/database.yml]] serializes these writes, including two first-enrollment attempts for the same phone. When a concurrent enrollment still saves the same phone first, the second save fails the phone's uniqueness validation or unique index, and both this callback and [[app/controllers/api/v1/registrations_controller.rb#RegistrationsController#callback|the mobile callback]] answer with the already-registered refusal instead of a save failure or a 500. [[app/frontend/hooks/authentication/useWebAuthnRegistration.ts#useWebAuthnRegistration|The browser registration hook]] displays the sign-in or support guidance on refusal without opening the device enrollment prompt. The enrollment start also requires a phone verified in this session that equals the submitted session phone; without one it answers 200 with `success: false` and the confirm-your-phone-first message, and the hook shows that message and stops before the passkey ceremony. A refused callback changes no account data and creates no signed-in session; every callback exit clears its challenge.

New users and existing phone-verified users with no passkeys can complete first enrollment. An unfinished address registration does not permit replacing an already saved passkey. The user resumes setup after signing in with that key. A failed passkey save rolls back the user write so enrollment cannot leave a partially updated account. A credential id or public key already held by another passkey counts as a failed save and gets the retry message. A sign-in failure after the commit keeps the account and passkey and redirects with a message to sign in with that passkey, because a retry would meet the existing-passkey refusal. A WebAuthn verification error in the callback redirects with one fixed sentence that tells the user to enter the phone number again, which the resume branch below accepts without a new SMS. The library's message never reaches the user, because a wrong origin or relying party is a Sway configuration fault, and Sentry gets only the exception class.

A phone verified in a web session counts for enrollment for [[app/controllers/concerns/verified_phone_session.rb#VerifiedPhoneSession#VERIFIED_PHONE_WINDOW|thirty minutes]]. A verification time is stored beside `verified_phone`, and [[app/controllers/concerns/verified_phone_session.rb#VerifiedPhoneSession#verified_phone_current?|one predicate]] is the only check, used by the enrollment start, the enrollment callback, the repeated Confirm code answer and the resume branch. A browser session can outlive its user, so without a bound a phone verified on a shared or borrowed browser would stay good for enrolling a first passkey for that number; the mobile token and the add-a-passkey window are already ten minutes. Thirty minutes covers a retried passkey step. A verified phone with no stored time counts as expired, which covers the sign-in writes that do not stamp one. Expiry costs the user one new code. The worst case is a named wait, because every send limit refusal states how long to wait; once the number's ten daily sends are used that wait can be most of a day, as [[phone-verification-rate-limits#Why one phone gets one code a minute and ten a day]] records.

### Enrollment credential metadata

Registration prefers discoverable passkeys so a device can offer them without a phone number. Authenticators without resident storage can still enroll and use phone-first sign-in.

[[app/controllers/users/webauthn/registration_controller.rb#RegistrationController#callback|Enrollment]] captures the authenticator's model identifier for a friendly device label. That identifier arrives only during registration, so older records without it cannot acquire a label through later sign-ins.

### Enrollment attributes exclude admin privileges

[[app/controllers/users/webauthn/registration_controller.rb#RegistrationController#sanitized_user_attributes|The enrollment attribute allowlist]] excludes admin privileges because session-carried profile data cannot authorize elevated access.

A new-account creation callback could mask an unsafe privilege assignment by resetting it. An existing account without passkeys also takes this enrollment path, so the attribute boundary protects both cases while preserving `:webauthn_id` (and mobile registration caches `webauthn_id` between `#create` and `#callback`) so the persisted `User#webauthn_id` matches the user handle embedded in the authenticator's resident credential.

### Admin and API phone lists represent separate privileges

[[app/models/user.rb#User#ADMIN_PHONES]] and [[app/models/user.rb#User#API_USER_PHONES]] are independently loaded credentials. Admin access follows only the former, while [[app/controllers/api_keys_controller.rb#ApiKeysController#verify_is_sway_api_user]] gates API key management on the latter; an API identity must not gain interactive admin rights merely because its phone is on the API allowlist.

### A rejected verification needs a parameter diagnosis

Twilio error 60200 identifies an invalid parameter, but the SMS verification report retains only its code and HTTP status. The planned diagnosis needs the rejected field before it can distinguish caller input from service configuration.

The existing error wrapper deliberately removes provider messages because they
can contain a recipient's phone number. That privacy boundary remains part of
the diagnosis: a provider-side record or a bounded field-name classification
can establish the cause without copying raw messages into application reports.
Code 60200 alone is insufficient evidence for changing phone validation or
silencing all verification failures.

### A number no US phone can have never reaches Twilio

The SMS endpoints refuse a number that North American numbering cannot assign before any Twilio call, because Twilio would only reject it after spending the user's attempt.

[[config/initializers/monkey_patches.rb#String#possible_us_phone?]] accepts exactly ten digits whose area code and exchange each start with 2 to 9, after the usual normalization strips a leading country code 1. The web code request, the mobile code request and the mobile code check answer 422 with "Enter a valid US phone number." for anything else. This rests on the numbering rule, not on Twilio error 60200 (see [[identity-and-access#Identity and access#The phone number is the account#A rejected verification needs a parameter diagnosis]]).

[[app/controllers/users/webauthn/sessions_controller.rb#SessionsController#create|The web sign-in start]] applies the rule only after its passkey branch, where it would otherwise send an SMS. A stored account whose phone fails the rule still gets the passkey flow, so the rule never locks out an existing user. The refusal is a 200 JSON answer, `flow` sms with `success` false and the "Enter a valid US phone number." `error`, because the caller is a fetch that cannot follow a redirect to a page and a 422 would send the panel to the SMS fallback; the stored phone and the account model's own phone validation are unchanged.

### A verification-not-found reply has one safe browser outcome

A Twilio verification-not-found reply returns one fixed message and stops the passkey flow.

For Twilio error 20404, [[app/controllers/phone_verification_controller.rb#PhoneVerificationController#update]] returns HTTP 200 JSON with `success: false` and `error: "Code not found."`. [[app/frontend/hooks/authentication/phone/useConfirmPhoneVerification.ts#useConfirmPhoneVerification]] shows that error as the notification title, falls back to `Incorrect Code` when the field is absent, and does not start passkey enrollment on failure. A rejected code leaves `verified_phone` unset and creates no user. Rate limiting remains a separate response path.

The controller logs only the phone's last four digits and provider code. It does not log the provider message or recipient digits; other provider failures are answered with HTTP 200, `success: false` and a fixed message, and reported to Sentry as a sanitized error built after the rescue block, with no raw provider exception as its cause ([[twilio-error-phone-redaction#Why a failed Twilio code check is reported and answered]]). [[twilio-error-phone-redaction#Why Twilio error handling redacts recipient identifiers]] documents the redaction boundary.

### A phone verified in this session confirms again without Twilio

A second Confirm code for the session phone that this session already verified answers success without asking Twilio again.

Twilio deletes a verification once it approves it, so a second check for the same phone answers 20404 and the user would see "Code not found." after dismissing the passkey prompt. [[app/controllers/phone_verification_controller.rb#PhoneVerificationController#update]] therefore answers `success: true` when `verified_phone` already equals the normalized session phone, after the blank and length checks and before any Twilio call. That branch writes nothing to the session: `verified_phone` is still set only by a Twilio approval or by the skip switch, and a different session phone still goes to Twilio. The answer grants nothing new, because the web enrollment start already accepts that verified phone until its window ends; once it ends, the confirm goes to Twilio again. Retried confirms still count against the update rate limits.

## Two voter-registration flags mean different things

`users` carries two booleans whose names read alike and whose meanings do not
overlap. Confusing them puts the wrong claim in front of a legislator.

`is_registered_to_vote` is a fact about the person: they say they are on the
voter roll somewhere. `LegislatorEmailText` reads it to decide whether an email
to a representative opens "I am registered to vote and" rather than "I", and the
legacy contact-legislator dialog gates on it.

`is_voter_registration_address_confirmed` is a claim about one address: the
person confirms the address they gave Sway is the address their voter
registration carries. It is what makes a constituent claim checkable against a
public voter file, which is the guarantee a representative actually needs.

The column defaults to false. A row that predates the question, or a
registration that left the box unticked, reads as unconfirmed, so silence is
never mistaken for a yes — the checkbox is a recorded answer, not a gate on
completing registration. `SwayRegistrationController#create` sets it from the
web form; the mobile address screen is the
remaining writer. Both read the shared wording at
`PARITY_COPY.address.helper.registeredVoterConfirmation`.

## User JSON exposes only selected fields

Sway exposes a reviewed list of user fields rather than Active Record's full row.

[[app/models/user.rb#User#as_json]] delegates to `to_sway_json`, which is built
from the explicit field list in [[app/models/user.rb#User#to_builder]]. This
prevents Active Record's default JSON serializer from exposing every database
column, including sign-in IPs, `webauthn_id`, and `sign_in_count`. The explicit
representation also derives admin status from the phone allowlist rather than
publishing a writable flag.

Mobile reads `current_user.theme_mode` through [[mobile/src/theme/ThemeProvider.tsx#ThemeProvider]]. The web reads the same saved preference through [[app/frontend/hooks/useTheme.ts#useTheme]] as `theme.preference`, so both clients restore the reader's stored appearance.

### Shared address props use an explicit field list

Web and mobile use [[app/models/address.rb#Address#to_builder]] instead of raw attributes, keeping precise coordinates and trimmed `street3` out of browser history while sharing the same public fields.

### Locale props are never cached once per browser

Locale collections in [[app/controllers/application_controller.rb]] depend on the signed-in user and admin status. Inertia must rebuild them per identity because once-props survive sign-in and sign-out redirects.

`locales_for_current_user` preloads `:current_legislative_session` via `ActiveRecord::Associations::Preloader` so mapping locales to JSON does not trigger an N+1 query when serializing each locale's `current_session_start_date`.

### Invite links are created with the account

[[app/models/user.rb#User#create_user_invite_url]] creates the invite link after the user row commits and does not regenerate it on later updates. This gives every newly created account one stable invitation link without making unrelated user edits trigger new links.

## Registration is asynchronous by necessity

`User` carries a `state_machines-activerecord` machine over
`registration_status` with two states: `pending` and `completed`.

[[app/models/user.rb#User#registered?]] is the one registration predicate used by authorization and response serialization. The compatibility completion boolean derives from active representative rows and the list of locales still waiting for representatives; workflow status describes progress only. A stale true cache grants no access, while an active row or a waiting locale can repair a `pending` status or a false cache through the completion event.

The predicate requires at least one active `UserLegislator` or at least one locale id on the pending representative list ([[registration-dead-ends#A skipped lookup is recorded so it can be retried]]); inactive historical rows do not count. A pending locale counts because an upstream outage never blocks registration: the user has finished every step of their own, and only Sway's lookup is outstanding, which a job assigns later. The completion event rejects a user with neither, and a rejected event rewrites the compatibility cache from the predicate, so switching off a user's last active row does not leave a true cache behind. After initialization, state-machine events are the only writers of the workflow status and compatibility cache.

A waiting user has no representative links to protect, so the two checks in [[app/controllers/sway_registration_controller.rb#SwayRegistrationController#create]] that run before the lookup, the address-switch confirmation and the early completion, test active links rather than the predicate. A waiting user who submits an address, the same or a different one, takes the first-registration path: the saved address is replaced and every locale of the submitted address is looked up again. Locale ids recorded for an earlier address stay on the list for the retry job.

Turning an address into legislators requires geocoding it and, for regional
locales, querying an external geo endpoint — work that can fail or
rate-limit. `SwayRegistrationService` executes inline during the request for
both local and regional locales and records any skipped or failed locale on
the user's pending representative list so background reconciliation can retry
it later without blocking sign-up.

Registration writes two things per matched legislator, not one: a
`UserLegislator` and a `UserDistrict`. The district link is what later lets a
bill's district-level tally be computed without walking back through the
legislator, and `ReconcileUserDistrictsService` exists to repair the pairing
when it drifts.

[[app/controllers/application_controller.rb#ApplicationController#authenticate_sway_user!]]
checks the predicate on each request. Active links self-heal a `pending` status
or a false completion cache through the completion event; no active links deny
access even when persisted status or cache says completed. The sign-in
locale-cookie gate in `ApplicationController` and the redirect gates in
[[app/controllers/home_controller.rb#HomeController#index]],
[[app/controllers/influence_controller.rb#InfluenceController#index]], both
branches of [[app/controllers/users/webauthn/sessions_controller.rb#SessionsController]],
and [[app/controllers/sway_registration_controller.rb#SwayRegistrationController#index]]
also use `registered?`. After address resolution,
[[app/controllers/sway_registration_controller.rb#SwayRegistrationController#create]]
reports success from active rows, not `completed?` alone.

[[app/services/skip_phone_verification_provisioner.rb#SkipPhoneVerificationProvisioner]]
does not write completion fields for a new account; existing registered users
keep their address, profile, and assignments.
[[app/services/sway_registration_service.rb#SwayRegistrationService]]
completes only after active rows exist. The seeded-user graph in
[[db/seeds/models/development_user_graph.rb#SeedDevelopmentUserGraph]] assigns
active links before completing users. The WebAuthn enrollment snapshot excludes
`is_registration_complete` and `registration_status`, so an old challenge
cannot restore stale completion state. The existing boolean field and response
key survive as derived compatibility data; they are not a second authority.
[[app/frontend/components/layouts/AuthLayout.tsx#AuthLayout]] and
[[app/frontend/pages/SwayRegistration.tsx#SwayRegistration]] consume the same
server-derived boolean. The mobile profile type keeps the existing response
shape, with `registration_status` as progress information.

[[mobile/src/navigation/RootNavigator.tsx]] requires
`user?.is_registration_complete === true` to enter the main drawer. A saved address
with a false or missing field remains in onboarding until the bootstrap supplies
authoritative true. The field name and boolean type stay stable in
[[mobile/src/hooks/useUserProfile.ts]]; there is no address-presence fallback.
[[app/models/user.rb#User#to_builder]] serializes the same derived boolean.
`AddressScreen` uses it for onboarding copy as well, so a
prefilled address does not complete registration.

[[app/controllers/sway_registration_controller.rb#SwayRegistrationController#create]]
returns HTTP 200 with the existing `{ok: true, registration_status:
"completed"}` success shape only when an active assignment exists. When the saved address is still unlocated after the lookups, the JSON body adds `address_located: false` and `message: ADDRESS_NOT_LOCATED_MESSAGE` while the browser redirects back to `/sway_registration` with the `address_not_located` flash outcome ([[registration-dead-ends#A skipped lookup is recorded so it can be retried#An unlocated address waits for its geocode]]). If
synchronous resolution returns none, it returns HTTP 422 with the standard
`{error: {code: "no_representatives", message: ...}}` envelope and a safe
message; the browser path redirects with the same reason rather than claiming
success from stale status. `AddressScreen` displays that HTTP error and does not
refresh the profile, so the user stays in onboarding.

### Registration service results preserve their rows

[[app/services/sway_registration_service.rb#SwayRegistrationService#create_user_legislators]]
returns the persisted `UserLegislator` rows. Returning the rows lets callers
work with the assignments themselves; a collection of save booleans would
discard that useful result.

### Regional lookup uses one configured request path

The regional OpenStates lookup preserves its configured request path.

The resolver reads its key once and reuses that value for both the blank
check and request, so the value checked is the value sent.
[[app/services/sway_registration_service.rb#SwayRegistrationService#find_legislators_from_open_states_geo_endpoint]]
uses the configured connection profile, wraps non-success responses as an
unavailable service, and treats a missing results array as no matches. A body
that is not an object, or a results array holding anything but objects, is
refused as an unavailable service too. It
matches returned person ids to each seeded legislator's external id. A blank
key returns no matches and sends one error-level Sentry message naming the key,
so registration still completes with the locale-wide officers while the gap
reaches the operator.

### Invite bookkeeping cannot abort registration

[[app/services/sway_registration_service.rb#SwayRegistrationService#create_invite]]
uses `create_or_find_by!` to resolve a concurrent invite create-or-find race.
A validation failure is logged and swallowed because invite bookkeeping must
not roll back a valid representative assignment.

### Mobile address actions follow registration status

[[mobile/src/screens/AddressScreen.tsx#AddressScreen]] uses the server-derived
completion boolean for onboarding mode. Cancel signs out during onboarding and
returns to the prior screen while editing an address.

### Address help links retain platform behavior

The mobile address helper keeps the same voter-registration note and three
external links as the web page. [[mobile/src/screens/AddressScreen.tsx#AddressScreen]]
opens those links with the platform URL handler; the web page opens a new tab.

### Browser and mobile preserve their response formats

Browsers use Inertia redirects; bearer and JSON clients receive JSON.

[[app/controllers/sway_registration_controller.rb#SwayRegistrationController#respond_json_or_redirect]]
keeps a JSON client out of the browser's Inertia redirect flow. The mobile
branch does not depend on `Accept: application/json` alone, so a bearer request
without that header still receives JSON. The same split applies to
no-representatives and transient geocoding failures.

### OpenStates system stubs exercise the request boundary

The system stub must reach the regional OpenStates request.

The spec sets a nonblank key because a blank key returns an empty result before
HTTP. It stubs the request with WebMock at the connection boundary used by
[[app/services/sway_registration_service.rb#SwayRegistrationService#find_legislators_from_open_states_geo_endpoint]],
so the test proves both that the lookup ran and that its result created an
active user-to-legislator link.

## A user holds one address

`User` declares `has_one :user_address` and `has_one :address, through:`, so one address per user is already the shape of the associations. A second row makes `user.address` an arbitrary pick.

Registering again replaces the address rather than adding one. Someone who moves,
or who corrects a typo in a street name, posts `/sway_registration` a second
time, and the earlier link is the stale one. Keying the join row on the
user-and-address pair, as `#create` once did, left an account holding every
address it had ever given, none of them removed.

The rule is a unique index on `user_addresses.user_id` rather than a convention
inside `SwayRegistrationController`. Three other writers create the same join
row — the skip-phone-verification dev provisioner, `db/seeds.rb`, and the
development user graph — and a rule kept only in the controller does not reach
them. `UserAddress` repeats it as a `uniqueness` validation, so a second row
fails with a validation error rather than a database exception. The migration
that adds the index deletes older duplicates first, keeping the newest row per
user; those rows are not recoverable from a rollback.

Two submits from one user, such as a double-click, can both find no link before either stores one. The request whose insert loses, to the validation or to the index, re-reads the stored row and points it at its own submitted address, as a sequential repeat does, so both requests answer success and the user keeps one row.

The provisioner is also why a system spec that calls `register_passkey_user`
already has a join row before its own setup runs. Those specs re-point that row
through `set_user_address` rather than adding a second one.

[[app/controllers/sway_registration_controller.rb#SwayRegistrationController#create]] checks [[app/models/user.rb#User#registered?]] when a user already has a [[app/models/user_address.rb#UserAddress]] row. Re-submitting the same normalized address, or the same text without coordinates ([[address-normalized-key#Finding an address during registration#A repeated unlocated submission reuses the user's own row]]), completes immediately, whereas switching to a different address requires `confirm_deactivate_legislators`, passes [[app/services/user_address_switch_service.rb#UserAddressSwitchService#cooldown_active_for?]], and reconciles districts, legislators, scores, and a [[app/models/user_address_change.rb#UserAddressChange]] audit row through [[app/services/user_address_switch_service.rb#UserAddressSwitchService#call]] only after representative lookup succeeds. Mobile navigation follows the derived completion boolean, not address presence.

## Sessions, cookies and bearer tokens

Web sign-in resets the session first, then issues an encrypted `refresh_token`
cookie and stores both `user_id` and an `auth_identity` stamp derived from the
account's creation time.

The reset guards against session fixation; the identity stamp guards against a
recycled user id resolving to a different account.

Web credential callbacks wait for [[client-caches-and-identity#Identity changes wait for network-only pages|identity-cache preparation]] before submitting. Credential payloads are JSON produced by credential.toJSON(), or built by hand in [[app/frontend/sway_utils/webauthn.ts#create|webauthn.ts]] with the same keys when the browser lacks the WebAuthn JSON helpers; their casts bridge Inertia RequestPayload typing without changing the wire data.

Phone confirmation uses PUT through Inertia's shared HTTP client because verification changes session state and requires CSRF protection. Successful confirmation awaits passkey creation and verification before returning, and includes registration loading in the panel busy state. Phone-first and discoverable callers also await verification so failures reach their existing error feedback. Discoverable cancellation leaves the phone form available; unexpected failures show retry guidance. Dismissing the browser's passkey-creation prompt (NotAllowedError or AbortError) is not a failure: it sends no toast or Sentry report and the code step shows a message that Confirm code tries again.

An existing stamp that differs from the account's created_at clears the stale
session identity; a valid refresh token can still recover authentication. A
legacy session with no stamp receives one. Guard specs distinguish a 401 without
a valid refresh token from the authenticated but registration-incomplete 403.

Registration returns JSON for a bearer header or JSON request format. A mobile
client omitting Accept must still receive JSON because it cannot continue into
the web Inertia redirect flow.

On shared routes served by `ApplicationController`, presented token credentials under either supported scheme (`Bearer` or legacy `Token`) are authoritative: a present token resolves identity via `ApiKey` and fails closed when invalid, expired, or revoked, never falling back to ambient cookies. The `Bearer` CSRF exemption is granted only to requests carrying a successfully authenticated bearer identity, preventing credential confusion and unauthorized state mutations.

[[app/controllers/api/v1/base_controller.rb#BaseController#current_user|Mobile account identity]]
comes only from an accepted API token, including the legacy Token scheme.
Session and refresh cookies cannot authorize account access or identify a user
on public bootstrap. Active keys without a device remain valid;
[[app/controllers/api/v1/base_controller.rb#BaseController#build_bearer_token_payload|mobile issuance]]
creates device-scoped keys with a 90-day expiry.

The mobile namespace uses null-session forgery handling rather than disabling
forgery checks. A valid Bearer request receives the shared CSRF exemption.
[[registration-funnel-telemetry#Ingestion API and rate limiting|Funnel telemetry]]
alone retains optional browser attribution when no token is supplied and its
credentials survive forgery handling: `FunnelEventsController` reads `session[:user_id]` directly rather than calling `authenticate_with_cookies` (avoiding `RefreshToken` rotation when `NullSession` clears the session), and `funnelTracker.ts` includes the page's CSRF token so same-origin browser beacons keep `session[:user_id]`. This exception grants no mobile account access.

When [[mobile/src/api/client.ts#request]] receives a 401, it clears the stored
token and session, closes the live ActionCable consumer, then emits
`unauthenticated` so listeners observe cleared credentials. The consumer import
stays inside that branch: it does not import the API client today, and the
deferred import avoids creating a cycle if that dependency changes.

On the device that key lives in the iOS keychain, read back once at launch to
decide whether anyone is signed in. That read is fail-closed in both
directions: an item that cannot be read counts as no session, and the
signed-in decision always settles. Leaving it unsettled is worse than being
wrong about it, because the root navigator renders an empty view while the
answer is pending, and the splash background is deliberately the same colour
as the app shell — so a read that never resolves is indistinguishable from a
launch that never finished.

### Sign-in counter failure is logged, not raised

`ApplicationController#sign_in` uses a non-bang save for sign-in counters so a
validation failure does not block authentication; it logs
`sign_in.counter_update_failed` instead.

### Signing out every device is atomic

[[app/models/user.rb#User#revoke_all_devices!]] revokes each active device and its API keys in one transaction. If a revocation fails partway through, rollback prevents the user from ending up signed out on only some devices.

### Signing out every browser

Each account carries a session generation, an integer that every browser session must match to stay signed in. Raising it ends every web session at once.

Web sessions live in Rails' cookie store, so the server holds no session row to delete. Deleting refresh tokens alone left another browser signed in, because its cookie still carried `user_id` and `auth_identity`. [[app/lib/browser_session.rb#BrowserSession]] therefore writes the account's generation into the session at sign-in, beside `auth_identity`, and every place that trusts a session cookie compares both through it: [[app/controllers/application_controller.rb#ApplicationController#authenticate_with_cookies]], the ActionCable connection, the admin direct-upload guard, funnel attribution and the test-only sign-in route. Without the cable check a disconnected browser would simply reconnect.

A session with no generation reads as 0. Authentication never fills the missing value in, the way it backfills a missing `auth_identity`, because filling it with the current value would undo a revocation. Sessions written before the column existed keep working until the account's first sign-out everywhere.

`POST /users/sign_out_all_devices` ([[app/controllers/users_controller.rb#UsersController#sign_out_all_devices]]) acts only on the signed-in account and carries Rails' CSRF check. [[app/models/user.rb#User#sign_out_all_devices!]] first deletes all of the account's refresh tokens and raises the generation in one transaction, then revokes every mobile device; the action then signs the calling browser out and redirects to the public home page.

The tokens go in the same transaction as the generation, not later in the ordinary sign-out. Otherwise another browser arriving in between is judged stale, finds its refresh-token cookie still valid, and is stamped with the new generation, so it stays signed in.

### A refused CSRF write leaves a fresh retry path

An invalid authenticity token redirects with both an alert and the machine-readable `page_expired` flag, so a redirected write cannot be mistaken for a successful save. [[app/controllers/application_controller.rb#ApplicationController#inertia_page_expired_error]] owns that refusal response.

Inertia follows the redirect with a GET, whose response sets a fresh `XSRF-TOKEN` cookie. The reader can retry the write with that token without manually reloading; the frontend checks `page_expired` because landing on the redirect target alone does not prove that the write succeeded.

### Refresh tokens bind to their issuing request

RefreshToken#usable_for? requires an unexpired token with the issuing IP address and user agent. Both HTTP and WebSocket cookie recovery use this predicate; it is separate from ActiveRecord model validation.

A WebSocket fallback that checked only token existence would admit cookies
the HTTP path rejects, including expired cookies on admin pipeline channels.
RefreshToken.for deletes every token by user_id inside a BEGIN IMMEDIATE
transaction before creating its replacement. Deleting through the singular
user.refresh_token association removes only one row and can leave an older
token behind; the transaction serializes overlapping rotations, and `ApplicationController#sign_out` deletes tokens both by the encrypted cookie value and by `user_id`.

### A reused browser keeps an earlier example's cookies

System specs drive one browser across examples without transactional fixtures, so a previous example's session, `refresh_token` and `auth_identity` cookies are still present when the next one starts.

`AdminSystemHelpers#sign_in_as` waits for `root_path` to finish loading, then deletes every cookie before opening a session through the test-only `/test/sessions` route. `Test::SessionsController` calls `reset_session` as well, and the two overlap deliberately: a surviving `auth_identity` that mismatches the looked-up user's `created_at` fails the stale-session check on the very next navigation, which signs the user out and returns the browser to the root page instead of the page the example asserts against.

### Request specs switch the complete authentication identity

Both request sign-in helpers replace user_id and auth_identity together. Retaining the first account's creation-time stamp makes a deliberate account switch look like a stale session.

The guard compares integer seconds, so two accounts created in one second can
hide an incomplete helper. The regression fixes their creation dates one day
apart and exercises both RequestSpecSessionHelpers and SessionDouble. Legacy
session coverage removes the stamp explicitly and verifies its backfill.

Registration address checks assert successful responses as well as row counts;
otherwise a rejected request could satisfy a no-new-row assertion without
testing address matching at all.

## The sign-in challenge says which ceremony to run

Both sign-in challenge endpoints answer a phone number with `passkey` or
`sms`, and the client runs whichever it is told. Naming the flow tells a
caller whether that number has an account, and that disclosure is accepted
rather than overlooked.

An insecure page context is reported before the browser's error is read at all.
The same slow refusal that means "the person declined" over https means "this
page cannot do WebAuthn" over http, so classifying by the error would blame the
reader for the address they arrived at.

The mobile endpoint used to refuse to say. It answered every number with a
challenge, real or built around a decoy credential, and left the device to
fail and the app to fall back to SMS. Two things undid it. The fallback had
never worked — the client matched error names the passkey library does not
emit — and the failure it was supposed to produce is a blocking iOS sheet
about passkeys, put in front of someone signing up who has never heard of
one. Meanwhile the web endpoint had been naming the flow outright the whole
time, so an attacker enumerating numbers had a surface regardless.

What defends account existence now is rate limiting, ten probes per address
and five per number every five minutes, on both endpoints. Discoverable
sign-in remains genuinely blind: it names no phone number, so it has nothing
to disclose.

### A phone confirmed in this session resumes enrollment

The web endpoint answers `enroll` instead of sending an SMS when the submitted phone has no passkey and equals the phone this browser session already confirmed.

A reload or a later return to the tab shows the phone form again, and without this branch the same number would cost a second SMS and a second code for a phone the session has already proved it owns. [[app/controllers/users/webauthn/sessions_controller.rb#SessionsController#create]] records the submitted phone as the session phone and answers `enroll`, and [[app/frontend/components/auth/PasskeyPanel.tsx#PasskeyPanel]] starts passkey enrollment straight away. Recording the phone grants nothing new: [[identity-and-access#Identity and access#The phone number is the account#First-passkey enrollment]] already accepts that verified phone inside its window, and a different number or an expired confirmation still takes the SMS branch. A phone with a passkey still gets the passkey flow first.

### Discoverable callback resolves the credential owner

The credential, not a phone lookup, identifies the account in a discoverable
sign-in.

[[app/controllers/users/webauthn/sessions_controller.rb#SessionsController#discoverable_callback]]
resolves the user from the returned credential id, then verifies that stored
passkey against that user's credentials. A guessed or mismatched id therefore
cannot authenticate as another account.

The native error is still the only signal the app has once a ceremony is
running, and it decides the rest: unsupported reaches a dead-end screen,
cancelled or no-credential follows the appropriate fallback, and unexpected
failures remain failures rather than being classified as missing passkeys.
Their cause may require separate diagnosis.

### Client origin logging excludes credential payloads

Passkey origin telemetry records the decoded origin, ceremony type, Android package, and request host; decode failures record only the exception class.

[[app/controllers/api/v1/base_controller.rb#BaseController#log_passkey_client_origin]] lets operators compare the client report with accepted origins without recording the challenge or full credential payload.

### A missing stored passkey must stop verification before key access

The web callback rejects an unknown passkey inside the credential lookup, before WebAuthn reads its public key. A missing database row is an authentication refusal, with the one-use challenge cleared.

Both web callbacks check the stored passkey inside the block passed to
verify_authentication. WebAuthn 3.4.3 dereferences the lookup result
inside that call, so returning nil raises NoMethodError before either friendly
refusal is reachable. Rejecting the credential with UnknownPasskeyError inside
the lookup halts verification safely, allowing the controller to rescue the
error and redirect with the appropriate refusal alert. Coverage for this
correction verifies that key access is attempted only on recognized passkeys.

### Mobile passkey error translation

NoPasskeyError names the app's missing-or-cancelled passkey outcome. It is an internal routing signal, not a claim shown to the user that every credential is missing.

The native library throws plain objects with error and message fields, not Error instances or code fields. UserCancelled and NoCredentials both map to NoPasskeyError because dismissing an iOS no-passkey sheet is indistinguishable from deliberate cancellation. Native names, no_passkey_enrolled server codes and the no_credential message remain unchanged.

Phone-first sign-in treats this outcome as the SMS path. The flow: sms response skips the native ceremony entirely, and the older no_passkey_enrolled API response remains compatible. Cancelling registration returns to the code form without displaying the internal message, so enrolment can be retried.

Only NotSupported from a sign-in ceremony, or from the support check before any ceremony, maps to PasskeyUnsupportedError, so the DeviceUnsupported screen is reserved for a device that cannot do passkeys at all. Registration has no support check, so it can never throw PasskeyUnsupportedError and never reaches that screen. NotSupported thrown by the create ceremony of a registration, after the code check passed, maps to PasskeyCreateUnsupportedError: on Android it comes from Credential Manager being unsupported or disabled, outdated Google Play services or an old OS, and the code step shows `passkeyCreateUnsupportedAndroid` (update system software and Google Play services) or `passkeyCreateUnsupportedIos` (update iOS), each ending with press Confirm code again and then another device or sway.vote, with the held SMS-verified token kept. The screen-lock sentence would not fix those causes, so this error is kept apart from PasskeyProviderMissingError. NoCreateOption is the native answer when the phone has no credential provider, for example Android without a screen lock or a Google account. It maps to PasskeyProviderMissingError, because the user can fix it, and so does BadConfiguration on Android during registration, which comes only from the WebAuthn ConstraintError. A sign-in BadConfiguration stays a plain Error and is reported to Sentry, so the user sees the generic sign-in error. Sway asks for required user verification, so that error means the phone cannot verify the user, for example because it has no screen lock. A broken asset-links file arrives as RequestFailed, not BadConfiguration. The code step shows `passkeyNoProviderAndroid` (screen lock and Google account), which is Android only because iOS never answers NoCreateOption, ending with press Confirm code again, and the held SMS-verified token stays so the retry needs no new SMS. On iOS BadConfiguration stays unmapped. It stays a plain Error carrying the native message. Other failures retain native details internally instead of being reclassified as missing passkeys. The library reports some real causes only as UnknownError or "Native error", for example iOS "device not configured" and Android NotConfigured (Google Play services), so the app cannot tell them apart. An unmapped failure thrown by the create ceremony of a registration therefore shows `passkeyUnidentifiedMobile` on the code step, which names the screen lock or passcode and up-to-date software as the likely fix and ends with press Confirm code again, and keeps the held token. The same kind of failure from the code check keeps the generic `verifyError`, since no passkey was involved. An unmapped, non-cancel failure is also reported to Sentry as the message `passkey_native_error` with the native error name as its only tag, never the detail text, the phone or a token. Development logging retains native details for diagnosis; the error tests use the library's actual object shape rather than an invented Error subclass.

#### A session the device cannot save

When the keychain refuses the bearer token or the session envelope after a successful callback, both stores are cleared and SessionSaveError is raised, so no half session remains.

By the time [[mobile/src/auth/passkeyAuth.ts#persistSession]] runs, the registration callback has already created the account, saved the passkey and consumed the SMS-verified token. Retrying the code step can only fail with an expired token, and a new code cannot help because the account exists. The only working path is passkey sign-in, which needs no SMS, so the error's message names it. Errors from clearing the stores are ignored, because the user's next step does not depend on them.

The code step answers SessionSaveError by returning to the phone form, which drops the held SMS-verified token and shows the passkey sign-in button, and displays the error's message. Sign-in shares the same callback path and keeps its existing sign-in error copy.

### Mobile passkey ceremonies

Discoverable sign-in sends no phone number, allowing the returned passkey to identify its account. Adding a passkey instead requires a fresh SMS verification token for the signed-in account.

Sign-in persists both the bearer token and session envelope. The envelope retains device_id so signing out can revoke this installation's device record. Adding a passkey leaves the current session intact and returns the new id and label for the account's list.

### Mobile authentication screen

The mobile auth screen keeps phone entry, code confirmation and progress in one flow. A code form appears only after SMS sending succeeds, so a failed send does not strand the reader waiting for a code that never left.

Preview Sway opens the public webpage because the signed-out navigator has no mounted application tabs. Successful authentication emits signed_in to switch navigator stacks. Unsupported devices use the dedicated screen. Auth screen tests include ThemeProvider because their controls consume theme context.

Unexpected sign-in failures show the same retry guidance on phone-first and discoverable paths. Native and API error details are not user copy. Only NoPasskeyError is silent on the discoverable path, leaving the phone form available; unsupported devices still reach their dedicated screen. Tests cover both error paths and preserve cancellation and SMS behavior.

## The one response whose body carries a secret is never stored

An API key is shown once, in a page object embedded in the HTML, so that one response is answered with `no-store`.

The value is encrypted in the session cookie and plain in the body, and Rails'
default answer for an authenticated page — `max-age=0, private,
must-revalidate` — permits the browser to keep that body on disk. `no-store`
forbids it, which is the difference between a secret that exists for one render
and one that sits in a cache directory.

## A passkey label is unique to its owner, not to the system

One person's passkeys each need a distinct label, so the management screen can list several devices and the owner can tell them apart.

Two different people may both call a device "iPhone", and forbidding that would
leak nothing useful and refuse an ordinary name. The uniqueness is therefore
scoped to the user, and a fixture that hands out labels from a counter is what
lets one account hold several passkeys — the multi-device exclude-list case —
without colliding. When a user adds another passkey without a custom label (or with the default `"New passkey"` or `"Passkey"`), the controller disambiguates it with a numeric suffix (`"New passkey 2"`, `"New passkey 3"`), while mobile callbacks validate the `Passkey` record before consuming `SmsVerificationToken` so a duplicate custom label returns 422 without burning the one-time SMS token.

## The rate limit store swaps in after boot

The probe limits above, and every other throttle in the app, share one
mutable store object because Rails 8's `rate_limit` reads its `store:`
option once, at class-load time, not per request.

`ApplicationController::RATE_LIMIT_STORE` is a `SwappableCacheStore`, a
thin wrapper that forwards everything through `method_missing` to a
`@backend` it can reassign later. Every rate-limited controller —
`CspReportsController`, `PhoneVerificationController`, the WebAuthn and
API v1 session, registration and device controllers, and the sign-in
challenge endpoints above among others — captures this same constant when
its class loads, so swapping the one backend object turns every limiter in
the app on or off together; no controller holds a limiter of its own.

The constant starts out wrapping a `NullStore`, a cache that discards
everything it is given. That default is deliberate: `NullStore#increment`
returns `nil`, which Rails 8 reads as "no requests counted", so a limiter
left unwired fails open and silent instead of raising at boot. Outside
tests, `config/initializers/rate_limit_store.rb` closes that gap in an
`after_initialize` block — run there specifically because it needs
`ApplicationController` loaded and `Rails.cache` configured — by pointing
the backend at `Rails.cache`. Every throttle mentioned above, and the
1000-per-IP limit in `ApplicationController`, depends on that swap
having run; skip it and the limiter still "works", it just never counts.
Tests take the same store through a third state instead: `with_rate_limit_enabled`
and `with_rate_limit_disabled` (`spec/support/rate_limit_helpers.rb`) swap in
a `MemoryStore` for the duration of an example and restore the `NullStore`
afterward, so a spec can prove a limit trips — or that it stays off — without
depending on `Rails.cache`.

Which concrete cache backs `Rails.cache` is a separate decision from this
wiring, and it has moved since: both serving environments now reach Solid
Cache, so a rate-limit counter survives a deploy rather than resetting with
the container's `tmp/` directory. The store itself is
[[auxiliary-databases#The Solid Cache database replaces two different broken caches|the Solid Cache database]].

## The admin gate is a lint rule

Administrative access is `before_action :verify_is_sway_admin`, and the set of
controllers carrying it is an explicit allowlist in `lib/tasks/sway_lint.rake`,
enforced by `rake sway:lint:admin_guards`.

An allowlist rather than a convention was chosen because the failure mode is
silent: a controller that loses its guard still works, still passes its own
tests, and exposes admin data. Every admin controller spec additionally
includes the `requires sway admin` shared example, so the guard is asserted
positively as well as linted.

One admin endpoint sits outside that mechanism. Active Storage's direct-upload
controller belongs to Rails and never reaches `ApplicationController`, so it is
guarded by `AdminOnlyDirectUploads` middleware instead — the deliberate
exception, not an oversight.

"Admin" unqualified means an organization-scoped admin. The
application-level role is always spelled `sway_admin`, per
[[naming-decisions#One term per concept]].

### The organization gate is linted the same way, for the same reason

Organizations carry their own gate, defined once on a base controller, and a
second lint task checks that every organization-admin controller declares it.

Its failure mode is the sitewide gate's: deleting the line broke no test, and
the endpoint would quietly open to any member. The base controller itself is
excluded because it only defines the method — it is a parent class with no
actions of its own to protect. One entry on the sitewide list is there because
that endpoint once had no gate at all, and any signed-in reader could set or
clear the Bill of the Month release date.

A third task in the same CI step runs the cop requiring a request spec that
checks Inertia props to name the page component it expects. No workflow runs
RuboCop on its own, so without the task the cop would never run and would
protect nothing. It declares no environment dependency, because the cop runs
standalone and booting the application just to lint spends CI time for nothing.

### Adding a passkey re-verifies by SMS first

A signed-in reader can opt in to add a passkey, and the flow asks them to
re-verify by text before it registers one.

Without that step a session left open — one somebody else has reached, or one
long past the moment its owner was present — could quietly register a new
credential that then grants entry on its own. The four endpoints behind it
mirror the sign-in ceremony's own, so the same evidence is demanded in both
directions.

The address the mobile sign-in screen opens in a browser is spelled with an
underscore because that is the Rails route. The hyphenated spelling reached the
catch-all and dropped the reader on the home page instead.

### An admin affordance in the reader's page is a convenience, not a gate

`BillEditLink` sends a Sway admin from a bill they are reading to that bill's
edit screen, and reads `is_admin` from the shared page props the layout
already carries.

Hiding it from everyone else saves a wasted click; it is not what protects the
edit screen. `verify_is_sway_admin` on the controller is the gate, and it holds
whether or not the link was drawn. The link is added at the page level, above
whichever themed layout the active theme picks, so all five bill layouts get it
identically rather than each growing its own copy.

The consequence for tests is that every suite rendering a bill row now renders
this link too, so each one has to supply page props. A suite that is not about
admin visibility supplies an empty props object, which is the signed-out case.

## Locale is part of the request

`set_sway_locale_id_in_session` resolves which jurisdiction a request belongs
to on every action, and the resolved locale plus the user's available locales
ride along as Inertia shared props.

Those locale props are deliberately never marked `once`. They vary per user,
and an Inertia `once` prop would let one user's locale list be served to
another from a cached page.

## The phone-verification bypass is inert outside development

The `SKIP_PHONE_VERIFICATION` setting reads as false unless the Rails environment is development or test, so no value that reaches production can switch the SMS check off.

The read sites in the controllers trust the setting as they find it, and none
looks at the environment; only
`SkipPhoneVerificationProvisioner` refuses to run outside a local environment,
and it runs after the check has already been skipped. Production was safe by
configuration alone: the name appears in neither `config/deploy.yml` nor
`.kamal/secrets-common`, so no value reaches the container. One mistaken entry
in either file could let anyone sign in as any phone number.

The gate lives on the setting's reader in `Sway::Settings::DevLogin` rather
than at the read sites, so a new site cannot forget it. Specs still toggle
the setting freely, because the test environment counts as local.

## The stand-in account borrows a jurisdiction's sample address

When phone verification is skipped, the account provisioned in its place still needs a real address, because a district and its legislators follow from one. That address is a property of a jurisdiction, not of the environment.

`sway_locales` carries `sample_street`, `sample_postal_code`, `sample_latitude`
and `sample_longitude` beside the city, state and country the row already
holds, so one locale describes one address inside itself. The four columns are
nullable. The production locales carry none of them, nothing in a deployed Sway
reads them, and a jurisdiction nobody has demonstrated has no honest value to
put there.

`SkipPhoneVerificationProvisioner` names the jurisdiction through one setting,
`DEV_ACCOUNT_SWAY_LOCALE`, a computed locale name defaulting to Baltimore's.
The obvious alternative, "the first locale", changes meaning silently the day a
locale is added, and the step runs during phone verification, before the person
has picked anything. A jurisdiction has no name for a person, so
`DEV_ACCOUNT_FULL_NAME` remains a setting; the six address values that used to
sit beside it are gone, two of them (`_CITY`, `_REGION_CODE`) having been a
second copy of columns the locale row already had.

Coupling the stand-in sign-in to seed data is what this costs. A locale row
with a sample address has to exist before the flow works at all, and a locale
without one makes the provisioner raise with that locale's name and the missing
column names rather than build an address out of nils. In development and test
the row is Baltimore's, seeded by `SeedSwayLocale` with exactly the street,
postal code and coordinates the Geocoder stub in `spec/rails_helper.rb` answers
with, so district assignment agrees with the stub instead of landing somewhere
else and failing in a way that looks unrelated. The address is Baltimore City
Hall's, a public office's published address rather than a person's home. It is
written into the seeder rather than into locale YAML documents, so the
seeded values and the stubbed values are both Ruby literals that change
together.

The four values are editable on the admin locales screen, which is what lets a
jurisdiction gain a sample address without a deploy.

### The bypass skips SMS, not address registration

The chosen local phone-verification shortcut skips SMS but still requires address-based registration.

The development and test shortcut verifies the phone step only and preserves
phone uniqueness. For a new user,
[[app/services/skip_phone_verification_provisioner.rb#SkipPhoneVerificationProvisioner]]
leaves the initialized compatibility cache false and workflow status pending;
it does not call the registration service or create representative links.
Address confirmation and active assignments remain necessary. If the
phone belongs to a user who already has active assignments, provisioning
preserves that user's real address, profile, and assignments, then heals only
derived completion state rather than replacing them with the sample address.

`spec/services/skip_phone_verification_provisioner_spec.rb` verifies that a new
user stays pending with no active `UserLegislator`, while an existing
registered user keeps its registration data.

### The phone-verification shortcut does not grant admin access

The development shortcut in [[app/services/skip_phone_verification_provisioner.rb#SkipPhoneVerificationProvisioner]] only skips SMS verification. It does not grant an administrative role: [[app/models/user.rb#User#is_sway_admin?]] still checks the configured [[app/models/user.rb#User#ADMIN_PHONES]] list.

### The primary development admin registers in Baltimore only

The development seed registers its primary admin in Baltimore City only through the configured local roster.

[[db/seeds.rb]] calls [[app/services/sway_registration_service.rb#SwayRegistrationService#call]] with `invited_by_id: nil`, using the committed Baltimore sample address and local geometry. With the configured roster and geometry, disconnected `db:seed` completes this registration and assigns the admin an active Mayor. Baltimore declares seat-keyed roster identity and curated office metadata in [[config/sway_locales/baltimore-maryland-united_states.yml]]. [[db/seeds/models/seed_legislator_terms.rb#SeedLegislatorTerms#configured_seat_context]] and [[db/seeds/models/seed_legislator_terms.rb#SeedLegislatorTerms#attach_configured_current_seat!]] persist the district-scoped current seat from that prepared roster. The mapping supplies office metadata, not published service dates; [[current-legislator-term#Which term a legislator is serving now#Roster identity during seeding#Configured office metadata for current seat-keyed rosters]] owns that distinction.

The seeded admin must have active Baltimore assignments including an active Mayor. Missing assignments, a missing Mayor, or unresolved or conflicting local office data raise visibly. This required local seed call adds no timeout and rescues no exception classes, so resolver and persistence failures escape.

### Each address field reads the column of the same name

The stand-in address takes each field from the sway locale column whose name matches it, and a crossed pair still produces correct-looking data for as long as the two sources are crossed the same way.

That is not hypothetical here. Back when the six address values were settings,
`postal_code` read `DEFAULT_REGION_CODE` and `region_code` read
`DEFAULT_POSTAL_CODE`, and every address came out right anyway, because the
`.env` files held those two values swapped as well. The crossing was invisible
until one of the two was corrected on its own.

The same pair is still adjacent in the same constructor, now reading
`sample_postal_code` and `region_code` off the sway locale row. Both are short
strings, neither is validated against a format, and a district assignment made
from a swapped pair fails somewhere else entirely — in geocoding, or in the
legislators that follow from it.

## Why UsersController#destroy revokes devices before cascading account deletion

[[app/controllers/users_controller.rb#UsersController#destroy]] revokes all mobile device tokens before destroying the authenticated [[app/models/user.rb#User]] record and clearing the web session cookie.

Self-service account deletion satisfies App Store account removal requirements while revoking bearer tokens first so no active mobile session survives the cascading deletion of user records. Account deletion completely cascades dependents across user-owned tables: votes, notification deliveries, organization memberships, passkeys, direct invites, sent organization invites, authored position changes, registration funnel events, authored bill summary reports, and received organization invites. In addition, shortened invite URLs owned by the user's invite link are removed through [[app/models/user_invite_link.rb#UserInviteLink]]. Database-level cascades similarly clear historical score explanations and historical repair deliveries.

Columns retaining rows on deletion are strictly limited to non-personal administrative references. At the database level, only `bill_summary_reports.resolved_by_id` retains its row. At the association level, nullify cascades are restricted to `resolved_bill_summary_reports`, `approved_position_changes`, and `rejected_position_changes` so administrative resolutions and review determinations preserve their historical outcomes without retaining personal user data. An automated deletion guard spec in [[spec/models/user_spec.rb]] verifies all foreign keys to `users` and limits nullify keys and associations to those explicit allowlists. The full set of dependent cascades is defined on [[app/models/user.rb#User]].
