---
lat:
  mode: explanation
---

# Organizations::MembershipInvitesController design notes

Design notes for Organizations::MembershipInvitesController: reactivating a departed member on accept, the dual web/mobile response shapes, the per-email rate-limit bypass it closes, and why redirects use 303.

## Why accept reactivates an existing membership instead of creating a new one

Someone who joined an organization once and later left still has a `UserOrganizationMembership` row, and the database allows only one row per user and organization — so creating a fresh one on re-accept would fail.

`#accept` finds the old row and switches it back to active instead of inserting a new one.

## Why create's per-email rate limit reads with params.dig, not invite_params

The per-email rate limiter reads the invitee email with `params.dig(:invite, :invitee_email)` rather than through the `invite_params` strong-parameter method.

A request that sends no `invite` key at all would make `invite_params` raise before the rate-limit block ever runs, letting a bot send bodies with no `invite` key to slip past the per-email limit entirely.

## Why create serves two response shapes

`#create` serves two clients: web (Inertia) gets a flash message and a redirect to the members tab.

`#create` serves two clients: web (Inertia) gets a flash message and a redirect to the members tab; mobile (bearer token) gets a 200 with no body on success, or the app's standard `{ error: { code, message, details } }` envelope on failure — a bare `{ errors: [...] }` body is unparseable by the mobile client. `redirect_or_json` (the `MobileFormatNegotiation` concern) is the redirect-flavored twin of `render_inertia_or_json`. Rate limits, the invite email, and the model's one-active-invite-per-person guard all still apply regardless of which response shape is used.

## Why failure responses also split by format

`respond_invite_failure` shapes its reply for whoever asked.

`respond_invite_failure` shapes its reply for whoever asked: JSON callers (the mobile app, with a bearer token) get the older `{ errors: [...] }` body, while browser and Inertia callers get a flash message and a 303 redirect, so the browser re-fetches with GET and the React confirm page shows the reason.

## Why redirects after a POST use status: :see_other

Inertia needs status 303 (See Other) after a POST, so the browser follows the redirect with a GET instead of repeating the POST.

## MemberInviteForm.tsx, the current (V2) member-invite form

Since `membership_invites#create` serves two different kinds of caller.

Since `membership_invites#create` serves two different kinds of caller — a web browser using cookies gets an Inertia redirect-after-post (a "PRG" pattern — Post, Redirect, then GET — plus a flash message), while the mobile app using a bearer token gets a plain 200 JSON response (see `MobileFormatNegotiation`) — this web form uses Inertia's `useForm`: success shows as a flash toast (matching the other membership and position forms), and validation errors render inline via `form.errors`. The Role control was removed — the server only accepts `invitee_email`, and every invitee joins as a `:standard` member.

Its submit handler nests the payload under `invite` to match `params.require(:invite)`; errors come back keyed by the model attribute (`invitee_email`), so `form.errors` still maps cleanly to the field.

## MembershipInviteConfirm.tsx, the frontend confirm page

`app/frontend/pages/organizations/MembershipInviteConfirm.tsx` asks someone to confirm they are accepting an invitation to join an organization.

`Organizations::MembershipInvitesController#confirm_accept` renders it on a GET. Accepting POSTs to that controller's `#accept` action through `useForm` — never a raw `fetch`. Rails names this page `Pages::ORGANIZATION_INVITE_CONFIRM = "organizations/MembershipInviteConfirm"`. A bearer or JSON request receives the same four props as JSON instead of the page, which is what the mobile app's confirm screen reads.

## Why members_tab_path pins to the members tab

`members_tab_path` points at the current admin's membership page, pinned to the members tab.

`members_tab_path` points at the current admin's membership page, pinned to the members tab — the surface that hosts the invite form — so both the success and the validation-error redirects from `#create` land the admin back where they were.

## useInviteAccept, the mobile hook

`useInviteAccept` (`mobile/src/hooks/useInviteAccept.ts`) accepts or turns down an invitation to join an organization.

The screen updates straight away rather than waiting for the server:

```
Accept:  POST  /organizations/:orgId/membership_invites/:id/accept
Decline: DELETE /organizations/:orgId/memberships/:id
```

The order is always the same: drop the invite from the screen, call the server, reload the list if it worked, put the invite back if it did not.

Pass a `refresh` function and it runs after a successful accept or decline so the list the invite came from can catch up.

## useMemberInvite, the mobile hook

`useMemberInvite()` (`mobile/src/hooks/useMemberInvite.ts`) lets an organization admin invite someone by email.

The invite is sent to an email address, not a phone number, even though a phone number is how Sway identifies an account elsewhere. The Rails side names the field `invitee_email`, so this hook posts `{ invite: { invitee_email } }` to match it exactly, and `MemberInviteForm` labels the box "Email".

Nothing is shown as done before the server says so: send the request, wait for the answer.

## Mobile: MembershipDetailScreen accepting an invite from a link

When the user arrives through a universal link and the membership is still "pending", `accept()` runs once as the screen appears, guarded by `acceptedRef` so it cannot fire twice.

On success the refresh redraws the screen with `status="active"`. On failure a banner appears with a Retry button.

## Mobile: MembershipInviteConfirmScreen, the confirm step for an emailed link

The link in an invitation email opens [[mobile/src/screens/MembershipInviteConfirmScreen.tsx#MembershipInviteConfirmScreen]] when the app is installed, so the invitee confirms in the app as they would on the web page.

The email link carries a signed token, not a membership id, so [[mobile/src/screens/MembershipDetailScreen.tsx]] and its automatic accept cannot answer it: that screen needs the membership the person does not hold yet. The confirm screen asks the server for the same four props the web page receives, shows the organization and the inviter, and waits for a press. Accepting stays a deliberate act on both surfaces, because opening an email link is not consent to join.

Accept posts to the same `accept` address the web form uses, with the token in the place of the id, and then replaces the screen with the memberships list, which loads fresh and shows the new membership. The token is percent-encoded once, where the screen reads it, before it goes into either request path.

Every failure is shown in the server's own words. A link that cannot be confirmed, such as an expired one, shows the message with a button to the memberships list. A failed accept shows the message above the button and leaves the button usable. A link with no usable organization id or token shows "Invitation not found." and asks the server nothing.

A second invite link can open the screen while it is already showing, because React Navigation updates the open screen's link values in place. The screen then drops what it showed for the first link, its errors included, and loads the new invitation.

A signed-out invitee reaches this screen after signing in ([[mobile-auth-and-onboarding-flow#RootNavigator#A link that arrives before the main screens is kept]]). No new claimed pattern is needed: `/organizations/*` already covers the email link on both platforms.

## Why UserOrganizationMembershipInvite derives status from timestamps instead of storing a state column

[[app/models/user_organization_membership_invite.rb#UserOrganizationMembershipInvite#status]] computes `:accepted`, `:revoked`, `:expired`, or `:pending` directly from `accepted_at`, `revoked_at`, and `expires_at` rather than persisting a state column.

Because expiry passes with wall-clock time (`Time.current > expires_at`) without a database write, a stored status column would go stale until a background sweep updated it. Deriving status in priority order — `accepted_at`, then `revoked_at`, then `expires_at`, then `:pending` — keeps the model free of a state machine and guarantees that an already-accepted or revoked invite never flips to `:expired` after its expiry timestamp passes.
