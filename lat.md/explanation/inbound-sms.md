---
lat:
  mode: explanation
---

# Inbound SMS

Texts sent to the Sway number reach one Rails endpoint, which updates the sender's notification flag and forwards anything that is real correspondence to an inbox. Nothing is answered by SMS.

## Twilio delivers each message to exactly one handler

An incoming message goes to a single webhook. The second field the Twilio
console offers is a fallback, reached only when the first one errors or times
out, so it cannot be used to send the same message to two places.

That constraint decided the shape. Everything inbound arrives at
`Webhooks::TwilioMessagesController`, and whatever else needs to happen with the
message happens inside Rails, where it can be tested.

Once a number carries an approved charity campaign, carriers check its traffic
against the campaign's registered samples, so a handler that relays arbitrary
messages back out through the number would be a standing risk to the
registration.

## The flag matters even though Twilio enforces opt-out

Twilio answers STOP at the carrier and blocks further delivery on its own, so
compliance never depended on Sway hearing about it.

What did depend on it is `users.sms_notifications_enabled`. Left stale, the
settings panel shows a green Enabled badge to somebody who has opted out, and
the services that enqueue `SmsDeliveryJob` keep queueing work Twilio silently
drops. The endpoint exists to keep Sway's own record honest, not to satisfy a
carrier.

## Keyword messages are not forwarded

A keyword is a command to the messaging system rather than correspondence.

Twilio has already replied to it, and `SmsOptOutService` has already acted on
it, so mailing it as well would put noise in the inbox on every opt-out —
exactly the moment when nobody needs a message.

The keyword sets live in `SmsKeywords` so the two readers cannot drift: the
service that flips the flag and the service that decides what to forward. A word
counts as a keyword only when it is the whole message, so a sentence that
happens to contain "stop" is still correspondence.

## The spam rule is a link from a stranger

Twilio has no inbound spam filtering, so any filtering is Sway's own.

The rule is deliberately narrow, because the number receives few messages and a
silent drop is worse than an unwanted email. A message is discarded when the
sender matches no `User` and the body carries a link, which is the typical shape
of spam. A known
user's message is always forwarded, links included, and a stranger writing plain
prose still gets through. The subject line names which of the two the sender
was, so the rest can be sorted by the mail client rather than by more code here.

## Suppression is only proved by running the job

The mail is enqueued rather than delivered inline, because a webhook that waits
on SMTP risks Twilio's fifteen-second timeout.

That makes the negative examples the delicate ones. A test asserting that
nothing was delivered passes trivially while the mail sits unexecuted in the
queue, so it would stay green even if the service forwarded every keyword and
every piece of spam. The specs run the enqueued job inline for that reason: only
then does a wrongly-forwarded message actually reach `deliveries` and turn the
example red.

## Forwarding goes to email, not SMS

Email is not A2P traffic.

It cannot be blocked by a carrier, it does not count against the registered
campaign, and it does not need the number to be registered at all.

## The number's notice cannot deny receiving messages

The fine print under the SMS panel must not tell users the number cannot
receive messages, because that would contradict the registered campaign.

Calls are genuinely dead: the number's voice URL is blank, which is Twilio's own
way of putting a number out of service for inbound calls, and costs nothing
because no call is ever answered. Messages are the opposite. STOP and HELP are
mandatory for a registered A2P campaign, carriers test them, and the campaign
declares both a help keyword and the reply it produces — so the number receives
messages by carrier requirement, and the consent copy instructs users to send
them in four separate places.

A notice denying receipt would be a claim the rest of the page disproves, on a
document a carrier reviewer reads while vetting the campaign. The wording
says calls are refused and that replies beyond the three keywords go unread,
which is true and still discourages anyone from treating the number as a support
channel. What stays unadvertised is the forwarding itself: nothing requires
telling users that ordinary correspondence reaches a mailbox.

The copy exists twice, in the V2 panel and the quarantined V1 one, and the two
are held to parity by hand.

## The keyword sets are pinned to the registered campaign

`SmsKeywords` has to be a superset of the words the A2P campaign told carriers
Sway accepts, or the two disagree about who is subscribed.

The registered opt-out set is OPTOUT, CANCEL, END, QUIT, UNSUBSCRIBE, REVOKE,
STOP and STOPALL; the opt-in set is SUBSCRIBE and START. Twilio honours all of
them at the carrier whatever the app does, so a user texting a word Sway does
not know still stops receiving messages — while `sms_notifications_enabled`
stays true and the sending services keep queueing work that is silently
dropped. That is the same stale-flag failure as
[[inbound-sms#Inbound SMS#The flag matters even though Twilio enforces opt-out]],
reachable through exactly the words the campaign advertised.

Sway's sets stay wider than the registered ones, because Twilio's own defaults
answer YES and UNSTOP too, and honouring a word the campaign did not list costs
nothing. The spec states the registered sets as literals rather than reading
them back from the code, so a word dropped from `SmsKeywords` fails the example
instead of quietly redefining what the test checks.

## The flag write skips validations

The opt-out write is `update_columns`, which bypasses both validations and the
`before_create` hook that resets several boolean columns.

`User` validates phone, email, name format and theme on every ordinary save. This
webhook flips one column on a row it already found by phone lookup, so running
those validations again would let an unrelated, pre-existing defect on that
record — a malformed name, a stale theme — swallow the opt-out. Somebody who
texts STOP is always recorded as having texted STOP.

`updated_at` is written explicitly because `update_column` would leave it stale.
Nothing keys a cache or a sync cursor off it today, so this fixes no live bug; it
keeps the row's modification time honest against a future ETag or incremental
query that would otherwise miss an opt-out.

## An unrecognised sender is not an error

A text from a number with no Sway account updates nothing and still answers 204.

Wrong numbers, numbers no longer attached to an account, and numbers that predate
Sway all reach a public phone number, and Twilio does not know in advance which
ones matter. `SmsOptOutService` returns when the lookup finds nobody. The
controller reports success either way, because from Twilio's side the webhook
was handled correctly and there is nothing worth retrying.
