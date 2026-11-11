---
lat:
  mode: explanation
---

# Organization invitation controller

The invitation controller returns browser redirects or mobile JSON while preserving the invite's validation and authorization rules.

## Creating an invite returns format-specific responses

Web and mobile invite writes return the response shape their caller expects and keep browser users in the members context.

Browser success redirects to the current admin's membership page with `org_tab=members` and a flash; validation failures return Inertia errors to that same context. Mobile success receives the redirect-and-flash JSON envelope, while validation failure returns the standard error envelope. [[app/controllers/organizations/membership_invites_controller.rb#MembershipInvitesController#create]] uses [[app/controllers/concerns/mobile_format_negotiation.rb#MobileFormatNegotiation#redirect_or_json]] only after a valid invite is saved. The request spec pins the mobile success and duplicate-validation responses.

## Why the invite email limit reads the raw nested parameter

The email-specific rate limit still runs when a request omits the invite hash.

[[app/controllers/organizations/membership_invites_controller.rb#MembershipInvitesController]] reads `params.dig(:invite, :invitee_email)` for this limit because calling the strong-parameter `invite_params` method before the limit would raise when `invite` is absent, bypassing that per-email check.

## Why accepting an invite redirects with See Other

After a successful POST, the browser must fetch the destination page with GET.

The acceptance action returns status 303 through [[app/controllers/concerns/mobile_format_negotiation.rb#MobileFormatNegotiation#redirect_or_json]] so Inertia follows the write with a GET rather than repeating the POST. The JSON client keeps its established redirect envelope.

## Why failed invite acceptance has format-specific responses

Browser acceptance failures return through a redirect, while JSON callers receive the existing error body.

[[app/controllers/organizations/membership_invites_controller.rb#MembershipInvitesController#respond_invite_failure]] keeps the browser's alert in flash and redirects with 303; JSON callers receive the legacy `{ errors: [...] }` shape. This differs from create validation, whose mobile response uses the standard `validation_failed` envelope.
