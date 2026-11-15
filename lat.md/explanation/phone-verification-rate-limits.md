---
lat:
  mode: explanation
---

# Api::V1::PhoneVerificationsController rate-limit design

Why a phone number gets at most one code a minute and ten a day, what else bounds code requests and registration spam, and why every phone-keyed limiter normalizes the number first.

## Why one phone gets one code a minute and ten a day

Each phone number gets at most one Twilio Verify send a minute and ten in any 24 hours, whichever IP address asks, counted across every path that starts a send.

The operator set this limit on 2026-11-14. It replaces, in part, the earlier decision that a one-time code had no per-phone cap at all. Four paths start a Verify send, and each asks the `phone_verification_send_wait` check in [[app/controllers/concerns/authentication.rb#Authentication]] before calling Twilio:

- [[app/controllers/users/webauthn/sessions_controller.rb#SessionsController#create]], the web phone-first sign-up
- [[app/controllers/phone_verification_controller.rb#PhoneVerificationController#create]] on the web
- [[app/controllers/users/passkeys_controller.rb#PasskeysController#verify_phone]], the re-verify before adding a passkey
- [[app/controllers/api/v1/phone_verifications_controller.rb#PhoneVerificationsController#request_code]] on mobile

The count lives in [[app/lib/phone_verification_send_limit.rb#PhoneVerificationSendLimit]]. Its cache key is the phone's HMAC digest from [[phone-cache-hashing]] alone; the client IP is not part of it. The operator chose this on 2026-11-14 because an IP adds nothing against an attacker with VPNs and proxies, who gets a fresh address for every send. A phone-plus-IP key gave that attacker a fresh allowance each time, so it capped nothing. The cost is that a stranger can use up a number's sends, but every refusal carries the real `Retry-After`, so the person is told how long to wait and is not stuck. The per-IP limits below stay as they are.

The 24-hour window is rolling, not fixed. The cache entry holds the times of the last ten sends for the phone. An eleventh send is refused until the oldest of those ten is 24 hours old. A refused send answers 429 through [[app/controllers/concerns/rate_limit_responder.rb#RateLimitResponder#render_rate_limited]] with `Retry-After` set to the real remaining wait: what is left of the minute, or the time until the oldest send leaves the window, whichever is longer. Twilio is not called. Because the stored send times give the exact wait, the reply never falls back to a whole window, so a refusal always says how long to wait and is never a dead end.

Twilio Verify has its own limits: five sends and five checks for one verification, which lasts ten minutes (errors 60203 and 60202). Sway's send limit does not sit below Twilio's: one send a minute allows six in five minutes, so a sixth send can reach Twilio inside one verification and is answered as described in [[phone-verification-rate-limits#Why one phone gets one code a minute and ten a day#A sixth send inside one verification is answered with a wait]]. Code checks are not counted here. They keep their own per-phone limit, five per ten minutes, which bounds guessing a code rather than sending one.

A send is counted once the check passes and before Twilio answers. A cache error lets the send through and is logged, because the rule against a failed registration outranks the cost cap.

The check sits behind the `:phone_verify` kill switch on all four paths, including the sign-up path, whose own sign-in limiters sit behind `:sign_in`. The passkey re-verify path keeps its older limit of three an hour per phone and IP pair, separate from the send cap and still keyed by both; it serves signed-in account holders only, so it cannot block a registration.

### The cooldown is claimed in one atomic write

The one-minute cooldown is its own cache entry, written only if absent, so of two requests for one phone in the same instant exactly one sends.

An earlier version read the send times and then wrote them back as two cache calls, so simultaneous requests could all read the same list and all pass. The cooldown write is now a single write-if-absent with a one-minute expiry: the request whose write lands sends, and every other request is refused with `Retry-After` taken from the stored start of the cooldown. Solid Cache in production checks and writes inside one transaction, which the SQLite configuration opens as immediate so no other writer runs between the check and the write, and the memory store the request specs swap in checks and writes under its own lock, so both stores honour it. The ten-a-day list is still a read followed by a write, but only the one request that won the cooldown reaches that write, so the list cannot be raced either.

When the write-if-absent fails but the cooldown entry can still be read, the request is refused with what is left of the minute, and with at least one second. The entry stores its start as a whole second but expires a minute after the real write time, so a request in that last fraction of a second would otherwise compute a wait of zero and send without a cooldown. When the write fails and no entry can be read, the send goes through and is logged, and the cooldown is written again without the absent check so the next request still sees it. That covers a cache that refuses writes and a cooldown that expired between the two calls; neither may block a registration.

### A send Twilio refuses gives its daily slot back

When the Twilio send call raises an error, that send's time is removed from the ten-a-day list, but the one-minute cooldown stays. A send call that returns counts as a send, whatever Twilio's reply holds.

During a Twilio outage every attempt fails. If failed sends kept their slots, ten failures would lock the phone out for about a day once Twilio recovered, and a person without an account must never fail to register. Keeping the cooldown still spaces retries a minute apart, so an outage cannot become a burst of requests. A send that timed out at Twilio may still have delivered the text; the slot goes back on every Twilio error, so each timed-out send that was still delivered goes uncounted. Only the one-minute cooldown and Twilio's per-verification limit bound those extra codes.

Two send paths give the slot back: the shared `send_phone_verification` in [[app/controllers/concerns/authentication.rb#Authentication]], used by the three web paths, and the mobile `request_code`, which calls Twilio directly. Each calls the same release helper when its Twilio call raised, and the helper removes only the time its own check recorded.

### A sixth send inside one verification is answered with a wait

Twilio refuses a sixth send inside one ten-minute verification with error 60203, and every path answers it as a rate limit that says to wait ten minutes.

The mobile request path and the three web paths (sign-up, sign-in resend and the passkey re-verify) turn that code into a 429 with `Retry-After` set to ten minutes, through the shared send helper in [[app/controllers/concerns/authentication.rb#Authentication]] and the mobile controller's own rescue, so a refusal always says how long to wait. The refused send gives its daily slot back like any other send Twilio refuses; the one-minute cooldown stays.

### The cooldown clock on Send a new code

The "Send a new code" control on the web passkey panel and the mobile sign-in screen shows a countdown to the next allowed send and stays disabled until it ends.

The clock starts at one minute, [[app/frontend/sway_utils/resendCooldown.ts#RESEND_CODE_COOLDOWN_SECONDS]], as soon as a code is sent, both when the code step first opens and after each new code. A user therefore sees the cooldown before ever meeting a 429. When the server refuses a send, the clock starts from the `Retry-After` it names instead. On the web, [[app/frontend/components/auth/PasskeyPanel.tsx#PasskeyPanel]] reads it through the toast handler that already words throttle replies. On mobile, the API client puts the header's seconds on the rate-limit error, as [[mobile-api-client-contract#Errors]] records. A refusal of the first code on mobile opens the code step with the clock set from `Retry-After`, whatever its size and including the daily wait, only when the same screen already sent a code to that phone, because that code may still be valid. The server keeps the cooldown after a failed delivery, so without such a send no code may be coming, and the phone form names the wait instead. On the web the existing throttle toast names it. The one-minute value must match the server's [[app/lib/phone_verification_send_limit.rb#PhoneVerificationSendLimit#COOLDOWN]], and both clients read it from the one shared module, so web and mobile cadence stay a single contract.

The wording comes from [[app/frontend/sway_constants/parityCopy.ts#PARITY_COPY]] on both clients: "Send a new code in 0:42" beside the button, and a spoken sentence such as "You can send a new code in 1 minute." for screen readers. The ticking clock is hidden from assistive technology, and the spoken sentence sits in a polite live region whose text changes only when a wait starts, so a screen reader hears the wait once rather than every second. The button keeps the plain "Send a new code" label. While waiting, the disabled button keeps three quarters of its opacity rather than half, so its label stays readable, and on mobile it keeps the 44-point minimum height of the shared pressable.

The clock on both clients subscribes to a one-second timer through React's external-store hook rather than an effect, the same pattern as [[use-active-theme-id-sync-external-store]]. The web panel's throttle latch uses the same hook. A refused new code starts this clock and never the latch on Confirm code, as [[passkey-panel-test-design#Why a refused new-code request must not latch the throttle]] explains.

## What else bounds code requests and registration spam

Per-IP limits sit above the per-phone send limit on every send path, and registration needs a verified code, so the whole chain stays bounded.

The web and mobile sends each allow 30 per hour per IP, behind the `:phone_verify` kill switch, so many people behind one carrier, café or event network can each get a code; Twilio Verify Fraud Guard, a Twilio console setting, is the primary guard on SMS cost. The sign-up send also passes the sign-in limiters: 10 per 5 minutes per IP and 5 per 5 minutes per phone and IP pair, behind the `:sign_in` kill switch. A user blocked by one of these Rails limiters is told to wait for its whole window, sent as `Retry-After` and worded by the web client as minutes or "about an hour", because the rate-limit store cannot say how much of that window is left, so the window is the honest upper bound; the add-a-passkey re-verify does the same for its hourly limiters, 10 sends per IP and 3 per phone and IP pair, and 10 code checks per IP and 5 per phone. Every other limiter keeps the one-minute default of [[app/controllers/concerns/rate_limit_responder.rb#RateLimitResponder#render_rate_limited]].

Registration spam needs a verified code, and a verified code needs a code request, so the chain `/verify -> sms_verified_token -> /registrations` is bounded by the per-phone send limit, the per-IP code-request limits, the sign-in limiters on the phone-first path, the per-verified-phone registration-start limits, and Twilio Verify's own limits on a phone number. A re-confirm of a phone already verified in the session makes no Twilio call and does not count against the code-check limit, so dismissed passkey prompts cannot lock the Confirm code button.

## Why spec/requests/rate_limiting_spec.rb stubs Twilio with a double

The endpoints this spec drives call `send_phone_verification` and `send_email_verification`, which build a real Twilio client out of environment variables.

Without a stand-in, these examples would pass only where the `TWILIO_*` variables happen to be set. On a bare CI runner the Verify service id is missing, and every send and check answers the handled outage reply described in [[twilio-error-phone-redaction#Why a missing Verify service id is answered like an outage]] instead of reaching the rate limiter. `TwilioDouble` sets a placeholder service id and stubs the client, which isolates the rate limiting these examples are actually about from that unrelated credential dependency.

## Why every phone-keyed limiter normalizes the number first

`normalize_phone` strips non-digits and drops a leading `"1"`, so every spelling of the same number — `"+1 (area)..."`, `"(area)..."`, `"1-area-..."` — lands in one rate-limit bucket.

An earlier bare `gsub(/\D/, "")` kept a leading `"1"`, so `"+1 (410)..."` and `"410..."` counted as two different numbers, doubling an attacker's per-phone budget. This same normalization is used everywhere a phone number becomes a rate-limit key: `Api::V1::PhoneVerificationsController`, `Api::V1::SessionsController`, and `Users::Webauthn::SessionsController`.

## Why passkey enrollment starts are rate-limited per verified phone

Answering `409 phone_already_registered` for a number that already has an account doubles as an oracle: without a limit, an attacker could learn which phone numbers are registered on Sway by submitting them one at a time.

Both enrollment starts answer that 409 only for a phone verified by SMS, so both are limited per verified phone: 20 starts an hour, behind the `RateLimitConfig.enabled?(:sign_up)` kill switch. The web start, `Users::Webauthn::RegistrationController#create`, keys on the session's verified phone. The mobile start, `Api::V1::RegistrationsController#create`, keys on the phone digest stored with the SMS verification token the request carries. A start with no verified phone, or with a token that is missing or unknown, is keyed on the client IP with the same limit, so probing without a verified phone stays bounded per IP.

A limit per IP would refuse the sixth new user an hour behind one carrier, café or event network, after their SMS was already sent and paid for, and one person cancelling the passkey prompt a few times would use up a shared IP's allowance. A limit per verified phone still bounds the oracle, because each probe costs a verified phone, and Twilio Verify's own limits bound how many phones one person can verify. A refused start sends `Retry-After: 3600`, the limiter's window.

The mobile limiter reads the token with a nested lookup that tolerates a request with no registration parameter, so such a request is counted against its IP and reaches the controller's own missing-parameter answer. Each limiter carries its own name, because Rails builds an unnamed limiter's cache key from the controller and the key value alone, which would share one counter with the application-wide per-IP limiter and count each request twice.

The `spec/requests/api/v1/registrations_spec.rb` rate-limiting examples tie the mobile limit to the `create` action, so detaching the two fails the test rather than silently going quiet again.

## Why the sign-in challenge throttles two ways

`Api::V1::SessionsController#challenge` and `Users::Webauthn::SessionsController#create` each allow 10 requests per 5 minutes per IP and 5 per 5 minutes per phone and IP pair.

Both endpoints sit on the sign-up path, so a limiter keyed by the phone alone would let anyone keep a stranger's sign-up refused by sending that number five times from anywhere. Keying the second limiter by the phone's digest from [[phone-cache-hashing]] joined with the IP still bounds account enumeration per network, and a person on their own network keeps their own allowance. Each limiter carries its own name, for the reason given under passkey enrollment above. Both clients get the same limits, so an attacker gains nothing by switching client, and every refusal on both sends `Retry-After` set to the 5-minute window.

The web limiter does not count a request for a phone this session has already confirmed. That request resumes enrollment without sending a code, and a person who dismisses the passkey prompt a few times would otherwise be refused at the step they had already passed, the same reasoning as the code-check limit's skip in [[app/controllers/phone_verification_controller.rb#PhoneVerificationController]].
