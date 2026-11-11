---
mode: explanation
summary: "Why WellKnownController serves the AASA/assetlinks/webauthn files on every host the mobile app claims, why the dev tunnel host is appended only in development, and why the AASA paths list is regression-tested against the route table."
status: agent-extracted
related: [docs/explanation/webauthn-settings-consolidation.md]
---

<!-- vale Vale.Spelling = NO -->

# `WellKnownController` design notes

This controller serves the WebAuthn "related origin requests" file and the
mobile app-link files (Apple's AASA, Android's assetlinks.json). Background:
[web.dev: WebAuthn related origin requests](https://web.dev/articles/webauthn-related-origin-requests).

## Why both hosts are authoritative

The mobile app's `linking.ts` targets BOTH `sway.vote` and
`app.sway.vote`. Apple and Google require the AASA and assetlinks JSON
files on the EXACT host the app claims, so both hosts are authoritative
here. The production reverse proxy (Caddy / Cloudflare tunnel) MUST
forward `.well-known/*` on both hosts to Rails — see the launch checklist.

## Why the dev tunnel host is appended only in development

A contributor running their own Cloudflare tunnel serves the app from a
host these lists cannot know in advance, and Apple/Google require the
association files on the EXACT claimed host. `dev_tunnel_host` returns
`nil` unless `Rails.env.development?`, so this is development-only:
production must never widen its host allowlist from an environment
variable.

## Why the AASA `paths` list is tested against the real route table

Every pattern in `#aasa`'s `paths` list has to match a real Rails route,
or iOS keeps handing that address to the browser and nothing anywhere
reports it. `well_known_spec` walks this list against the route table. It must be kept in step with
`mobile/src/navigation/linking.ts` and the Android intent filters in
`mobile/app.config.ts`.

## Why the request spec compares against Android's list, not just asserts it

Android's assetlinks carried its own, shorter path list than iOS's AASA,
so a membership link opened the app on iPhone and the browser on
Android — and a code comment claimed the two lists matched when they did
not. `spec/requests/well_known_spec.rb` compares the two lists directly
rather than asserting each in isolation, because comparing them is the
only thing that actually keeps that claim true.

## Mobile: `deepLinkPatterns.ts`

`mobile/src/navigation/deepLinkPatterns.ts` lists the addresses this app
claims, in Apple's wording, because Rails serves exactly this list at
`/.well-known/apple-app-site-association`. A spec compares the two, so
changing one without the other fails.

A hyphenated `/bill-of-the-week` matched nothing for months: the Rails
route is underscored.

Android matches a path by prefix, by exact value, or by a limited
pattern — never by Apple's glob, so each one has to be translated
(`androidPathData`):

A prefix is only usable when the trailing `*` is the ONLY one. Reaching
for it whenever a pattern merely ENDS in `/*` turned
`/organizations/*/memberships/*` into the prefix
`/organizations/*/memberships`, which no real address begins with — so the
membership link stayed broken on Android, which is the whole thing
this fix set out to repair.

The trailing slash is KEPT. Apple needs a character after it, so
`/bills/*` leaves the bills list to the browser; an Android prefix is a
plain string prefix, so dropping the slash claims `/bills` and
`/billsomething` as well and the two platforms disagree again.

## Mobile: `linking.ts`

`mobile/src/navigation/linking.ts` says which web addresses open which
screen in the app. The list of prefixes must contain both
`https://sway.vote` and `https://app.sway.vote`. Apple and Google only hand
a link to the app if the exact host serves the small proof-of-ownership
file they look for, and Rails serves that file on both hosts. Any address
on either host that matches a path below opens the app instead of a
browser. The `sway://` scheme keeps working too, for links used inside the
app itself.

`DEEP_LINK_PATTERNS` is the claimed list. Rails serves it in the ownership
file, and a web link to anything else here opens the browser however well
the app could answer it. Eight of the paths are claimed:

- `bills/:id` — a bill's detail. It is registered in both the Home and
  Bills tabs, so the link opens inside whichever tab the reader was
  already in.
- `bills` — the bills list
- `legislators/:id` — a legislator's detail
- `legislators` — the legislators list
- `bill_of_the_week` — the Bill of the Week. Underscored, because that is
  the Rails route; a hyphen here matched no address at all.
- `organizations/:orgId/memberships/:id` — one membership
- `organizations/:id` — an organization's detail
- `organizations` — the organizations list

`profile`, `sign-in`, and `users/organization_memberships` (the
memberships list) stay unclaimed on purpose: each shows
something that differs by who is signed in. A public page reads the same
for everyone, so opening it in the app is simply better; a personal page
does not — a web link that opens the app on a sign-in wall is worse than a
browser page that shows the reader why. Those three answer `sway://` links
from inside the app only.

### Why `androidPathData` must never hand back a prefix containing a star

A prefix carrying a literal star is the failure case above happening
again: it reads as a working translation rule and matches nothing.

## `deepLinkPatterns.test.ts`: the third link in the deep-link chain

Rails and the phone agree on the list (above), and the list translates
correctly into Android's wording (`androidPathData`, above) — and both of
those can be true of an address no screen answers. Then the app opens to
nothing, which reads to a person as the app being broken rather than the
link being unclaimed. `mobile/__tests__/navigation/deepLinkPatterns.test.ts`
adds that third check: every pattern in `DEEP_LINK_PATTERNS` has to match a
route `linking.config` actually serves. `/bills/*` and `bills/:id` are the
same address written two ways: one segment at a time, a literal must match
and a wildcard answers a name. Unanswered patterns are collected rather
than asserted one at a time, since Jest's `expect` takes no message, so an
empty list is what puts the offending address in the failure.
