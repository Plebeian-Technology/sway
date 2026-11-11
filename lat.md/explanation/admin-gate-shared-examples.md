---
lat:
  mode: explanation
---

# Admin-gate shared examples

Request specs use shared examples to prove authorization gates block the wrong identity and allow the right one.

## Admin phone overrides keep array semantics

[[spec/support/setup.rb]] replaces the admin and API phone constants with a one-element array containing the fixture user's phone.

The application checks membership in these arrays. Replacing either with a bare string changes the operation from exact element lookup to substring matching, so the test override must preserve the production shape. The global RSpec around hook restores both constants after each example.

## The admin trait replaces the configured phone list

The `:sway_admin` factory trait replaces `User::ADMIN_PHONES` with its own user's phone, so one example must not create a second trait user while relying on the first user's admin access.

The LLM-settings race uses a plain registered second editor because it needs another audit identity, not a second admin. Creating another `:sway_admin` would revoke the first fixture's gate before its save.

## The Sway admin gate has two refusal shapes

[[app/controllers/application_controller.rb#ApplicationController#verify_is_sway_admin]] returns 403 for JSON or bearer clients and redirects browser requests to the root path.

[[spec/support/shared_examples/requires_sway_admin.rb]] recognizes exactly those outcomes. A broader “any redirect” check could mistake a successful action redirect or an incomplete-registration redirect for an admin refusal.

## Admin refusal must precede resource lookup

The Sway admin gate runs before controller actions resolve bill or organization ids.

Using a nonexistent resource id in shared coverage ensures a non-admin is refused by authorization before a missing record can determine the response. Direct tests for write actions also assert that protected state remains unchanged.

## Incomplete registration can mask the admin gate

The non-admin examples give their fixture user an active representative link before issuing the request.

The authentication filter runs before the Sway admin gate. Without an active link, the request would stop at registration and leave the authorization check untested. [[identity-and-access#Identity and access#Registration is asynchronous by necessity]] defines the active-link predicate used for this boundary.

## Bearer authorization must replace any cookie identity

The bearer example clears the session user before sending its token and asserts JSON 403 with no `Location` header.

Some including specs set a file-level session user. That cookie identity takes precedence over the Authorization header, so leaving it in place would exercise the admin path rather than prove that a non-admin bearer is refused without a browser redirect.

## The permitted request must not swallow spec failures

The shared Sway admin example treats a controller exception as evidence that the admin gate allowed the request, but re-raises RSpec expectation and mock failures.

A permitted action may fail later because its feature-specific fixture is incomplete. Swallowing every exception would also hide broken assertions and mock expectations, turning a broken shared example green.

## Organization-admin refusal is identified by status or flash

The organization gate can redirect to a user-specific membership page, so its refusal cannot be matched against one fixed URL.

[[spec/support/shared_examples/requires_organization_admin.rb]] accepts a 403 or the exact Forbidden flash set by the gate. Checking only redirects could mistake the authentication filter's registration redirect for a refusal by the organization-admin gate.

## Missing API credentials stop before the admin decision

The API admin gate checks `performed?` after the required-key authenticator, because Rails may already have rendered its plain-text 401 response.

[[app/controllers/application_controller.rb#ApplicationController#is_api_request_and_is_route_api_accessible?]] must stop after that response; treating the authenticator's render return value as success would try to render a second response. The admin-specific message is reserved for a valid key whose owner lacks Sway-admin access.
