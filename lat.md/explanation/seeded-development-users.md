---
lat:
  mode: explanation
---

# Seeded development users

The development seed builds a graph of two hundred Baltimore users so score and notification surfaces have data. Those users carry phone numbers, and a phone number in a database that a job can reach is a phone number that can be texted.

## Synthetic users resolve district coverage through active representatives

[[db/seeds/models/development_user_graph.rb]] stores active representative links and no `UserDistrict` rows. District score coverage follows those links to the legislators' districts, keeping the fixture graph distinct from real address registration, which records user-district history.

## Graph users complete after assigning representatives

The fixture completes synthetic users through the state machine after active representative links exist.

This keeps cached workflow state consistent with the pairing evidence used by [[app/models/user.rb]] and avoids marking a user complete before its graph is built.

## Seeded users carry numbers no carrier will route

`phone_for` mints numbers in the unassigned 333 area code, so a message addressed to a seeded user cannot reach a subscriber even if something sends one.

The numbers were previously drawn from the `410-600` exchange upward. That reads like a placeholder and is not one: 410 is Baltimore's own area code and 600 is a live, assignable exchange within it, so the two hundred seeded users held two hundred numbers that belong to real people in the city Sway serves. Anything that sent to them sent to strangers, and the resemblance to the locale being seeded is what made the range look safe.

The 333 area code is not assigned in the North American Numbering Plan, so no carrier has a route for it and delivery fails at Twilio rather than at a handset. The formally reserved fictional range is the `555-01xx` block, which is the convention the rest of the repository follows, but it holds only one hundred numbers per area code and the seed needs two hundred distinct ones. An unassigned area code gives the same guarantee without a ceiling.

The seeded users are also marked `is_phone_verified` and half of them `sms_notifications_enabled`, because the notification surfaces are part of what the seed exists to demonstrate. Those flags are what put the numbers in range of a sender, so the safety has to live in the numbers themselves.

## Seeded legislator votes retain their resolved term

The seed resolves a term for each bill and legislator before inserting a vote, and stores that term identifier on the row. This keeps seeded votes tied to the office window used by term-scoped score recomputation.

## Score refresh follows current legislator terms

The score pass keys legislator and user-representative scores by active term.

Its legislator query also joins through the term, so the graph spec gives every seeded representative a current term with its district and title before running the pass.

## Factory users draw from the same unroutable range

The `:user` factory numbers its users through a sequence in the same unassigned 333 area code, one block above the seed's, so a suite run cannot invent a stranger's number and cannot collide with a seeded one.

The attribute was `Faker::PhoneNumber.cell_phone`, which draws from the live plan: every `create(:user)` minted a number that a carrier would route, and the suite creates thousands of them. Nothing sends to a factory user today, but the guarantee is worth more as a property of the data than as a claim about which specs happen to enqueue a job.

Determinism is the second reason. `spec/support/setup.rb` copies the phone it gets straight into `User::ADMIN_PHONES` and `User::API_USER_PHONES`, and the users table holds a unique index on the column, so a random generator's collisions surface as an unrelated failure in whichever spec drew the duplicate. A sequence cannot repeat itself, and it counts from a different exchange than the seeder's, so a spec that runs both still ends up with distinct numbers.

## Outbound SMS is refused outside production

`SmsDeliveryJob` declines to call Twilio unless the environment is production or `allow_nonproduction_sms` is set, because every outbound message in the application funnels through that one job.

Four separate paths enqueue it — the bill-of-the-week announcement, the voting reminder, the organization-follower notification and the daily and weekly digests — and each one selects its recipients by `sms_notifications_enabled` and `is_phone_verified` rather than by anything environment-aware. Three of those paths are scheduled in development as well as production, and a development machine can hold working messaging credentials, so a development jobs container could send real messages on a daily schedule.

Guarding the job rather than the schedules is what makes the guarantee hold. Removing an entry from the development half of `config/recurring.yml` would stop one trigger and leave the organization-follower path, which fires from an admin action rather than a clock. The job is the single place all four converge.

The setting defaults to false and is read through `Sway::Settings.ops`, so a developer who genuinely wants to watch a message arrive on their own handset can turn it on for that session, and nobody gets it by default. This mirrors the reasoning that already keeps `VotingReminderJob` out of the development schedule, recorded in [[scheduled-job-monitoring#Scheduled job monitoring]] — the difference is that the guard now covers the paths a schedule cannot.

The guard covers the messaging path only. Twilio Verify sends its own SMS server-side from `Authentication#send_phone_verification` and from the mobile endpoint beside it, and both were already short-circuited by `SKIP_PHONE_VERIFICATION`, which every environment template sets and whose reader is inert outside a local environment — see [[identity-and-access#The phone-verification bypass is inert outside development]]. A second guard there would duplicate a switch that already holds.

One specification depends on the setting: `spec/jobs/sms_delivery_job_spec.rb` performs the job and expects a Twilio call, so it turns the switch on and turns it back off in the examples that pin the refusal. Everywhere else Twilio is doubled and WebMock refuses `api.twilio.com` outright, so nothing reaches the network either way. The guard closes the development gap, not a test one.
