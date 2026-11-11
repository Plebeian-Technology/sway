---
mode: explanation
summary: "Why spec/system/organization_invite_spec.rb splits the invite/accept flow across two examples, and why the invite-saved assertion checks the database instead of the post-submit URL."
status: agent-extracted
related: []
---

<!-- vale Vale.Spelling = NO -->

# spec/system/organization_invite_spec.rb design notes

## Why the flow is split across two examples

The first example covers the admin's side — opening the organization's
membership page, opening the invite form, typing the invitee's email, and
submitting — then fakes the invitee's membership by writing it straight to
the database, so the whole admin UI does not have to run twice inside one
example. The second example does the invitee's side for real: sign in as
the invitee through the test-only `/test/sessions` route (no passkey
needed in tests), open the signed confirm-accept URL, click "Accept
Invitation," then check the redirect, the now-active membership, and the
`accepted_at` and `invitee_user_id` fields on the invite row.

## Why the invite-saved assertion checks the database, not the URL

After the admin submits the invite form, the browser could end up
anywhere — the form posts JSON to `/organizations/:id/membership_invites`,
and nothing about that response is a reliable page to assert against. The
example checks the database instead: one
`UserOrganizationMembershipInvite` row exists for the invitee's email.
