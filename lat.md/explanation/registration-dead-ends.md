---
lat:
  mode: explanation
---
# The dead ends in registration

Registration can end on a card with nothing on it to press. Each such card carries the one control the reader needs to get out of it.

## Correcting an address after a failed lookup

[[app/frontend/pages/SwayRegistration.tsx#SwayRegistration]] keeps a local flag that, once set, lets the reader past the failed card and back to the address form on the same page.

An address lookup can fail because of a typo, an address outside the supported jurisdictions, or a temporary upstream outage. For a first registration a failed lookup in one locale is skipped and reported, and registration completes with the locales that resolved ([[sway-registration-controller-notes#Why one locale's failed lookup is skipped and reported]]); only a registered user's address switch still answers the outage message, which the browser sees as a flash and JSON clients receive as the same safe error in their response format. A first registration never ends with no representatives ([[registration-dead-ends#An empty list says which kind of empty it is]]); only a registered user's address switch that resolves nobody returns `no_representatives` with a safe message.

The flag lives in the component rather than on the server because nothing about the account changes when the reader decides to try again. `SwayRegistrationController#create` accepts a fresh address whatever the current registration status is, so the corrected address takes the same path the first one did. The page asks for the address-switch confirmation only when `is_registration_complete` is true, as the server does, because an unfinished first submission already saved an address but created no representative links to deactivate.

It is cleared again when the server answers, in the form's `onFinish`. Without that the flag was one-way: a corrected address that failed for the same reasons as the first one re-rendered the page with the failed status and the reader still saw a bare form, with nothing saying the second attempt had failed either. Clearing it on every answer means the state the server reports is what decides which card shows, and the flag only ever covers the round trip.

A request that fails without a server answer the page renders leaves the form usable. A non-Inertia error page or a dropped connection shows one error toast in `PARITY_COPY` and suppresses Inertia's raw-response dialog, and the address stays in the form with the submit button enabled so the reader can press it again. Finishing the visit dismisses only the loading toast, whose id the page keeps from the moment it starts, because Inertia runs the finish callback after the failure callbacks and a bare dismiss would remove the error toast, or the "page expired" flash that a refused CSRF write redirects with, the moment it appeared.

### A President link alone is not a registration

A user whose only active links are to the President and who still has a locale waiting is treated as unregistered, so a corrected address registers directly.

An address with no coordinates and no state resolves to Congress alone and links only the President ([[representative-resolution#Congress fallback]]). If that user corrected the address, [[app/controllers/sway_registration_controller.rb#SwayRegistrationController#create]] would take the address-switch path and answer a 422 confirmation plus a 30-day cooldown for a switch away from a link that was never a real pairing. The check in `holds_representatives?` skips both the switch and the early completion in that case and runs the lookups for the new address.

## A failed address switch changes nothing

A registered user's confirmed address switch that fails while resolving the new address answers `registration_unavailable` with HTTP 503 and leaves the old address and links in place.

A first registration completes with whatever resolves, because a new user has
nothing to lose. A switch is the opposite case: the user already has active
representatives, and a half-applied switch would deactivate links they still
hold. [[app/services/user_address_switch_service.rb#UserAddressSwitchService]]
resolves every locale before it writes anything, so an error raised during
resolution leaves the account as it was. The controller turns any such error,
other than the geocoding outage that keeps its own `geocoding_unavailable`
answer, into a retryable message and a Sentry report instead of a 500. The
browser gets the message as a flash alert on the registration page, and a JSON
client gets it in the error body.

## An empty list says which kind of empty it is

An empty legislators list has two meanings, and they call for opposite things
from the reader.

Waiting for representatives means the answer is coming and there is nothing to
do; having no representatives means something needs correcting. One set of words
for both leaves a reader either acting on a screen that is about to fill itself,
or waiting for a screen that never will.

A first registration never ends in the second meaning. The address is accepted
as a fact and always reaches the Congress locale
([[representative-resolution#Congress fallback]]). When every locale's lookup
finishes with no active link and no locale recorded for a retry,
[[app/controllers/sway_registration_controller.rb#SwayRegistrationController#wait_for_congress_representatives]]
logs it, reports it to Sentry as a warning naming the user and the locales,
records the Congress locale on the waiting list
([[registration-dead-ends#A skipped lookup is recorded so it can be retried]]),
and the user is completed with the ordinary completion answer. An address whose
US state is unknown still resolves the President from the seeded roster
([[official-service-evidence#The curated President record]]), so it does not
reach this path. The
`no_representatives` refusal remains only for a registered user's address
switch that resolves nobody, which keeps the previous address and links.

The active-link success rule and browser, JSON, and mobile response shapes are
owned by [[identity-and-access#Registration is asynchronous by necessity]]. A
finished empty job ends in failure and records the safe no-representatives
funnel reason; transient failures keep their retry behavior below.

[[app/jobs/sway_registration_job.rb#SwayRegistrationJob#perform]] does not
leave a finished lookup in `processing` when it created no active link.

### The browser example waits for the address form beacon

The browser example for an address that resolves nobody holds its POST until the page's mount beacon has answered, so the POST's session cookie is the last one the browser applies.

Mounting [[app/frontend/pages/SwayRegistration.tsx#SwayRegistration]] sends an `address_form_viewed` beacon through [[app/frontend/sway_utils/funnelTracker.ts#trackFunnelStepOnce]]. The beacon is an ordinary request to a controller under `ApplicationController`, whose after-action [[app/controllers/application_controller.rb#ApplicationController#forbid_storing_a_one_time_secret]] reads the flash, and its response rewrites the session cookie.

The wait was added when the example read the no-representatives message from the flash, which lives in the session cookie. A beacon sent before the POST answered carried the older cookie and its response replaced the one holding the flash; a beacon sent after the POST consumed the flash. The example now checks the completed user and the feed redirect instead, which carry nothing in the flash, and keeps the wait so the POST still follows the page's own mount request as a person's submit would.

Unloaded, the beacon finishes about 30 ms before the example's POST, and load removes that margin. [[spec/system/user_registration_spec.rb]] holds the POST until the page's Resource Timing buffer lists the beacon. An entry appears only once the response has arrived, so the browser has already applied its cookie.

## Transient failures retry before registration becomes terminal

Transient upstream errors remain retryable until attempts are exhausted.

[[app/jobs/sway_registration_job.rb#SwayRegistrationJob#perform]] re-raises
errors in the job's transient set so Active Job can retry them; only the exhausted-retry callback marks a
still-processing user failed. Permanent errors mark the user failed
immediately. The failure helper uses `find_by` so a deleted user cannot hide
the original job error with a second `RecordNotFound`.

## A skipped lookup is recorded so it can be retried

A registration that skips part of a locale records that locale's id on the user, in `pending_representative_locale_ids`, so its representatives can be assigned once the upstream recovers.

[[app/controllers/sway_registration_controller.rb#SwayRegistrationController#create]] records two kinds of skip: a locale whose lookup raised, and a locale whose [[app/services/sway_registration_service.rb#SwayRegistrationService]] run skipped a term whose seat could not be resolved. A locale id is enough for both, because a retry of a locale re-runs every part of it, so the record does not need to say which part failed. [[app/models/user.rb#User#add_pending_representative_locale]] adds an id only once, so a locale skipped again leaves one copy, and [[app/models/user.rb#User#remove_pending_representative_locale]] takes it off.

A JSON column on the user is the simplest storage that fits: the list holds at most the three locales one address reaches, belongs to one user, and is never queried by locale. A registration with no skip leaves it empty. Three places read the list: the hourly job below, [[app/models/user.rb#User#registered?]], which counts a pending locale as a registration, and [[app/controllers/sway_registration_controller.rb#SwayRegistrationController#holds_representatives?]], which decides whether a President link alone is enough. No prop or JSON body exposes it. Every add and remove re-reads the row under a lock before it writes, so the reconcile job and the hourly job, which can run at the same time, never overwrite each other's change.

[[app/jobs/reconcile_user_districts_job.rb#ReconcileUserDistrictsJob]] records the same list for an existing user. It runs after every locale seed, and when one user's reconcile raises (a Census outage, a skipped term) it adds that locale to the user's list before moving on, so the hourly job below retries it. This is how users registered before the President term existed receive the President: the seed's reconcile run links them, silently ([[representative-reassignment-notifications#Notification delivery and preference governance#The President is linked without a notice]]), and an outage during that run defers the link to the hourly job instead of dropping it. A user with no address has nothing to look up and is skipped.

### The hourly job assigns what was skipped

[[app/jobs/assign_pending_representatives_job.rb#AssignPendingRepresentativesJob]] runs at quarter past every hour in development and production, and retries each recorded locale for every user whose list is not empty.

Each retry is one [[app/services/reconcile_user_districts_service.rb#ReconcileUserDistrictsService]] call for the user and the locale, against the user's current address. That service raises while an upstream is down or while a term is still skipped, so a call that returns means the whole lookup of that locale succeeded and its difference is applied. A user with no pending locale is never looked up, so a cleared record ends the retries for that user.

The id comes off the list only when the call returns and the user then has at least one active representative link. A lookup that returns but still gives a user no link at all keeps the id, so that user stays waiting and the next run tries again. A call that raises also keeps the id. The failure is logged for that user, and the job goes on to the next locale and the next user. The job never changes the registration status.

A lookup can stay down for hours while many users wait on the same locale, so one report per user per run would bury one outage under copies of itself. The job therefore counts failed users per locale during the run and, after the loop, sends one Sentry report per failing locale, carrying the first error, the locale name and that count. A locale that keeps failing produces at most one report each hour.

The schedule entry has its own presence check in `spec/config/recurring_spec.rb`, because the job spec proves only that the job works when something runs it ([[recurring-yml-registration-checks#Why spec/config/recurring_spec.rb checks registration, not just shape#Why specific tasks get their own "is registered" guard, not just the generic checks]]).

### An unlocated address waits for its geocode

An address the geocoder could not locate is recorded with every locale it reaches, Congress always among them, and the hourly job geocodes it again before any lookup.

A failed geocode leaves a typed address without coordinates, and a street-only one also without a state, so it resolves to Congress alone and links only the President. That link alone would make the user count as registered with nothing left to retry. [[app/controllers/sway_registration_controller.rb#SwayRegistrationController#create]] therefore records the address's locales whenever the address is still unlocated after resolution.

[[app/jobs/assign_pending_representatives_job.rb#AssignPendingRepresentativesJob#address_located?]] runs [[app/models/address.rb#Address#geocode_and_save]] for such a user first. While the geocode still fails, the job still runs the lookups, because Congress resolves the Senators and the President by state without coordinates, so a lookup left pending by a seat error or an outage is retried. It keeps every id, because a lookup that returns with the President linked would take the id off. Once it succeeds, the filled row's locales are added, since a geocoded state reaches locales the blank row did not, and the lookups run against the filled row. A located address goes straight to the lookups as before.

## Reaching sign-in from an expired session

The card shown when the page loads without a user says to sign in again, so it carries a link to `ROUTES.signin` — the same route the signed-out nav item uses.

The instruction used to name an action the screen did not offer: there was no button and no link. The link is an Inertia link rather than a plain anchor, so it behaves like every other in-app navigation, and its wording lives in `PARITY_COPY` with the rest of the registration copy rather than in the markup.

## Submitting the typed address when no complete suggestion is picked

The page posts what the user typed. The structured fields exist only after a suggestion is picked, so the autocomplete keeps the typed text in the form, the box shows it from there, and the submit fills `street` from it when no street is held.

The operator decided that a user's address is accepted as a fact, so a missing house number or postcode must not stop a sign-up. A road-only or postcode-less suggestion keeps its other fields and gains the typed text as its street, and a complete suggestion posts as before. A pick of a place with no house number takes its street from the text typed before the pick, because the pick then replaces the typed text with the place's full description, and that description is not a street. The typed-text key is removed from the body at request-build time, and nothing on the page blocks or warns before the post.

The structured fields always describe the text in the box. Editing the text clears every field a pick filled, and a pick replaces all of them, writing an empty value for any the place lacks and recording its description as the typed text. A stale street, postcode or coordinate from an earlier pick therefore never posts under a newer address.

## An address search that finds nothing or fails still says the typed address can be submitted

Under the address box, a polite status message follows each finished search that gave no list, so the user is never left with a silent empty box.

The autocomplete hook reports `ZERO_RESULTS` for an empty answer and `ERROR` when the request fails or returns the wrong shape, and the component picks one of two `PARITY_COPY.address.search` sentences from that status. Both sentences say the address can still be submitted as typed, which is true because the page posts the typed text. The message is hidden while a search is loading, because the hook keeps the previous status until the new answer arrives. It uses `role="status"` and leaves the input's `aria-invalid` alone, since the form error display is separate.

The server answers an empty list when Nominatim itself fails, so an upstream outage reaches the browser as `ZERO_RESULTS` and shows the no-results sentence rather than the unavailable one. The `ERROR` sentence appears only when the browser cannot reach the autocomplete endpoint or gets a malformed answer.

## Browser page state selectors

The browser and component specs use stable selectors to identify registration outcomes.

[[app/frontend/pages/SwayRegistration.tsx#SwayRegistration]] exposes distinct selectors for processing, failure, retry, sign-in, address submission, and the no-representatives result. This lets tests assert which outcome is rendered without depending on component internals.
