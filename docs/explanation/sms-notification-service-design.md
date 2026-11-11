---
mode: explanation
summary: "Explains why SmsNotificationService finds opted-in users through active legislator links instead of the user_districts table, and why the locale filter skips districts entirely."
status: agent-extracted
related: []
---
<!-- vale Vale.Spelling = NO -->

# Why SmsNotificationService resolves membership through legislator links

`SmsNotificationService.send_bill_of_the_week_notification` finds the
users who opted in to texts and belong to a bill's locale by working from
the user's ACTIVE legislator links, not the `user_districts` table. An
earlier version went through `user_districts` and matched nobody in
production, because only the development seed data ever filled that
table in — real signups (`SwayRegistrationService`) only create legislator
links.

The locale filter reads `sway_locale_id` straight off the legislator
rather than hopping through districts. Going through districts would
require each legislator to have a current term, quietly dropping anyone
between terms.

## Why the opt-out suffix is appended once, in `SmsDeliveryJob`

Four call sites enqueue `SmsDeliveryJob`:
`SmsNotificationService.send_bill_of_the_week_notification`,
`SmsNotificationService.send_voting_reminder`,
`NotifyOrganizationFollowersService#dispatch_immediate`, and
`DigestOrgNotificationAggregator.dispatch_period`. Carrier compliance
(A2P 10DLC) requires every outbound message to carry opt-out
instructions. `SmsDeliveryJob#perform` appends `OPT_OUT_SUFFIX` to
`body` once, in the job, rather than each call site appending it to the
string it builds. A call site that forgets is the actual compliance
risk — TCR sample messages must match real traffic — and centralizing in
the one path all four sites already share removes that failure mode for
any future send path too, not just the four that exist today.
`#append_opt_out_suffix` no-ops when `body` already ends with the
suffix, so a caller that starts including it directly (or a retried job
body) never gets it twice.

## Why the voting-reminder wording is short

`send_voting_reminder` reads `Sway: You haven't voted on this week's bill
in {city}: {title}. Vote now!` rather than the longer, more explanatory
`Reminder: You haven't voted on the Bill of the Week in {city}: {title}.
Vote now on Sway!` it used before. The shorter wording is a cost
constraint, not a style preference.

A GSM-7 SMS segment holds 160 characters, and Twilio bills per segment.
The old preamble spent 70 characters before the bill title began. Once
`SmsDeliveryJob` started appending `OPT_OUT_SUFFIX` for carrier
compliance, that left too little room: measured against the 51 real bill
titles in
`db/seeds/data/united_states/maryland/baltimore/bills.json` (35 to 54
characters, all ASCII) and the longest locale name, 15 of 51 crossed 160
characters and became two segments. None had before the suffix existed.
The shortened wording brings that to 0 of 51, with the longest rendering
at 151 characters.

The Bill of the Week alert was never at risk — it peaks at 140
characters with the suffix — so only this one message changed.

Anything added to this string eats the same headroom. Before lengthening
it, re-run the measurement against real titles rather than a typical
one: the average title is 45 characters and the constraint only bites at
the top of the range.
