---
mode: explanation
summary: "Explains the id-enumeration impersonation threat against organization membership invites and the signed-token + email-binding defense, plus the replay and expiry cases covered alongside it."
status: agent-extracted
related: ["docs/explanation/org-position-change-approval-spoofing-security.md", "docs/explanation/org-positions-membership-idor-security.md"]
---

# Organization invite id-enumeration security

`spec/security/organization_invite_security_spec.rb` guards
`Organizations::MembershipInvitesController` against three related failure
modes.

## The threat

Someone could once accept an invite meant for another person by guessing its
database id. Two things block that now:

- The invite id in the URL is a signed token, not a bare row id.
- The controller compares the signed-in user's email with the invited email
  using `secure_compare`.

Both `#confirm_accept` and `#accept` look the invite up with
`find_signed!(purpose: :accept_invite)`.

## What else the spec covers

The other examples cover replaying an invite that was already accepted, and
using an expired token.

## Why the URL's organization id is checked against the token's

Both `#confirm_accept` and `#accept` additionally check that
`invite.organization_id` matches `params[:organization_id]`. The signed
token alone proves the invite is genuine, but not that it was issued for
the organization named in this URL — someone holding an invite to
organization A must not be able to open the confirm page (or accept)
under organization B's URL.

## Why an expired signature and an expired `expires_at` column both answer 410 Gone

A token whose signature has lapsed raises
`ActiveSupport::MessageVerifier::InvalidSignature`. Both actions route that
rescue down the same "gone" path as the `expires_at` column check, so the
user reads one expiry message ("Invitation expired.") either way — the two
checks guard the same condition from different angles (a signed token can
expire on its own schedule, independent of the column), and the response
should not depend on which one caught it.

## See also

- `config/routes.rb` — `GET confirm_accept` and `POST accept`, both taking the
  signed token as `:id`.
- `app/controllers/organizations/membership_invites_controller.rb`
