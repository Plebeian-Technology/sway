---
mode: explanation
summary: "Why spec/system/user_registration_spec.rb calls SwayRegistrationService directly to reach the background-job registration path, and how its statewide examples prove the OpenStates lookup actually ran."
status: agent-extracted
related: [sway-registration-service-design.md]
---

<!-- vale Vale.Spelling = NO -->

# spec/system/user_registration_spec.rb design notes

## Why the background-job examples call the service directly

`SwayRegistrationController#create` always runs registration inline now,
so the background-job path (pending, then processing, then completed) can
only be reached by calling `SwayRegistrationService` directly —
`UserLegislatorsController#create`, for example, runs it in the background
by default. These examples call the service with `async: true` after
setting up the address, while still watching the processing screen in a
real browser, so the path that does exist stays covered end to end. The
failure example follows the same pattern to reach the job's failure path,
which is worth checking against the error screen the user actually sees;
a geocoding error while the job runs is what makes it call `mark_failed!`.

## Why the statewide fixture uses a matching city and region name

The async examples use a statewide locale rather than a city one, because
a statewide registration is what actually routes through the background
job. A statewide locale is built with its city name matching the region
(`city: "maryland", state: "MD"`), which is what makes
`SwayRegistrationService`'s `regional?` check true. For a statewide
locale, `SwayRegistrationService` asks OpenStates instead of SwayGeocode,
so the stubbed OpenStates response returns the legislator's `external_id`
so the inline part of the job ends up creating a real `UserLegislator` —
replacing the empty-results fake set up in the outer `before` block, since
the most recently registered WebMock stub wins.

## Proving the OpenStates lookup actually produced the result

After a statewide registration completes, the example checks that the
OpenStates request was actually made AND that the created `UserLegislator`
matches the stubbed legislator. Without both checks the example would
pass as soon as `SwayRegistrationJob#perform` calls `user.complete!`,
which it always does regardless of the lookup's outcome — so it could not
tell a working statewide lookup apart from one that had been deleted
entirely.
