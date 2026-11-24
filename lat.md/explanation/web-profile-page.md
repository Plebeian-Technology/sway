# Web profile page

`GET /profile` renders [[app/frontend/pages/Profile.tsx#Profile]], the one web page that gathers a signed-in reader's account pages, as the mobile Profile screen does.

[[app/controllers/users/profiles_controller.rb#Users#ProfilesController]] sits behind the usual sign-in check, so a signed-out visitor is redirected with the same notice as every other signed-in page. The page reads the name and phone from the shared user prop rather than a prop of its own, so it shows the same identity the navigation already trusts.

Its labels come from the `profile` block of the parity copy, which [[mobile-profile-and-delete-account-screens#ProfileScreen]] also reads, so the two clients name each row the same way.

## Why one Profile item replaces the Passkeys item

The navigation had grown one item per account page, and a page reached only through a browser feature check was easy to lose.

The navigation now carries a single Profile item for readers and in admin mode ([[system-shape#Auth navigation]]). Notifications stays reachable from the Profile page even when the browser lacks the Notification API, because its SMS settings work without push. The memberships link stays in the navigation as Organizations as well, since it is also a reader's way into their organizations.

## Why the API keys link is a page prop

API keys stay limited to the phone allowlist behind [[app/models/user.rb#User#is_sway_api_user?]], and only allowlisted users see an API Keys link.

The flag travels as the page's own `can_manage_api_keys` prop rather than a field on the shared user JSON, so no other page learns who is allowlisted and the [[identity-and-access#Identity and access#User JSON exposes only selected fields|user JSON field set]] stays unchanged.

## Deleting the account from the web

The Delete Account button asks for confirmation in the shared confirm dialog, naming what is lost, then sends `DELETE /users/:id` with Inertia for the reader's own id.

[[identity-and-access#Why UsersController#destroy revokes devices before cascading account deletion|The destroy action]] refuses any other id, revokes mobile devices, signs the browser out and redirects to the public home page with history cleared. On success the page also runs [[app/frontend/hooks/authentication/prepareIdentityChange.ts#clearIdentityCaches]], the same cache purge an identity change uses, so no page data from the deleted account stays in the tab. The dialog copy matches the mobile delete sheet ([[mobile-profile-and-delete-account-screens#DeleteAccountScreen]]).
