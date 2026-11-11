---
lat:
  mode: explanation
---
# The dead ends in registration

Registration can end on a card with nothing on it to press. Each such card carries the one control the reader needs to get out of it.

## Correcting an address after a failed lookup

[[app/frontend/pages/SwayRegistration.tsx#SwayRegistration]] keeps a local flag that, once set, lets the reader past the failed card and back to the address form on the same page.

An address lookup can fail because of a typo, an address outside the supported jurisdictions, or a temporary upstream outage. A transient geocoding outage rolls back assignments across all locales and leaves registration available for retry; the browser sees the outage message and JSON clients receive the same safe error in their response format. A synchronous lookup that succeeds but creates no active representative link is a different outcome: it returns `no_representatives` with a safe message rather than marking registration complete.

The flag lives in the component rather than on the server because nothing about the account changes when the reader decides to try again. `SwayRegistrationController#create` accepts a fresh address whatever the current registration status is, so the corrected address takes the same path the first one did.

It is cleared again when the server answers, in the form's `onFinish`. Without that the flag was one-way: a corrected address that failed for the same reasons as the first one re-rendered the page with the failed status and the reader still saw a bare form, with nothing saying the second attempt had failed either. Clearing it on every answer means the state the server reports is what decides which card shows, and the flag only ever covers the round trip.

## An empty list says which kind of empty it is

An empty legislators list has two meanings, and they call for opposite things
from the reader.

Waiting for registration to finish means the answer is coming and there is
nothing to do; having no representatives means something needs correcting. One
set of words for both leaves a reader either acting on a screen that is about
to fill itself, or waiting for a screen that never will.

The active-link success rule and browser, JSON, and mobile response shapes are
owned by [[identity-and-access#Registration is asynchronous by necessity]]. A
finished empty job ends in failure and records the safe no-representatives
funnel reason; transient failures keep their retry behavior below.

[[app/jobs/sway_registration_job.rb#SwayRegistrationJob#perform]] does not
leave a finished lookup in `processing` when it created no active link.

### The browser example waits for the address form beacon

The no-representatives message reaches the page through the flash, which lives in the session cookie, so a concurrent request can lose it before the page reads it.

Mounting [[app/frontend/pages/SwayRegistration.tsx#SwayRegistration]] sends an `address_form_viewed` beacon through [[app/frontend/sway_utils/funnelTracker.ts#trackFunnelStepOnce]]. The beacon is an ordinary request to a controller under `ApplicationController`, whose after-action [[app/controllers/application_controller.rb#ApplicationController#forbid_storing_a_one_time_secret]] reads the flash.

Two orderings lose the message. A beacon sent before the address POST answers carries the older cookie, and its response replaces the cookie that holds the flash. A beacon sent after the POST answers carries the flash, consumes it, and responds without it. Either way the page renders a complete address form with no message and nothing rerenders it, so a longer wait on the message cannot help.

Unloaded, the beacon finishes about 30 ms before the example's POST, and load removes that margin. [[spec/system/user_registration_spec.rb]] holds the POST until the page's Resource Timing buffer lists the beacon. An entry appears only once the response has arrived, so the browser has already applied its cookie.

## Transient failures retry before registration becomes terminal

Transient upstream errors remain retryable until attempts are exhausted.

[[app/jobs/sway_registration_job.rb#SwayRegistrationJob#perform]] re-raises
errors in the job's transient set so Active Job can retry them; only the exhausted-retry callback marks a
still-processing user failed. Permanent errors mark the user failed
immediately. The failure helper uses `find_by` so a deleted user cannot hide
the original job error with a second `RecordNotFound`.

## Reaching sign-in from an expired session

The card shown when the page loads without a user says to sign in again, so it carries a link to `ROUTES.signin` — the same route the signed-out nav item uses.

The instruction used to name an action the screen did not offer: there was no button and no link. The link is an Inertia link rather than a plain anchor, so it behaves like every other in-app navigation, and its wording lives in `PARITY_COPY` with the rest of the registration copy rather than in the markup.

## Browser page state selectors

The browser and component specs use stable selectors to identify registration outcomes.

[[app/frontend/pages/SwayRegistration.tsx#SwayRegistration]] exposes distinct selectors for processing, failure, retry, sign-in, address submission, and the no-representatives result. This lets tests assert which outcome is rendered without depending on component internals.
