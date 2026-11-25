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

[[identity-and-access#Why UsersController#destroy revokes devices before cascading account deletion|The destroy action]] refuses any other id, revokes mobile devices, signs the browser out and redirects to the public home page with history cleared. When the account is gone the page also runs [[app/frontend/hooks/authentication/prepareIdentityChange.ts#clearIdentityCaches]], the same cache purge an identity change uses, so no page data from the deleted account stays in the tab. A refused delete also lands as a successful Inertia visit, back on the Profile page with an alert, so the page purges only when the returned page no longer names the same signed-in user; a refusal keeps the reader's caches and local drafts. The dialog copy matches the mobile delete sheet ([[mobile-profile-and-delete-account-screens#DeleteAccountScreen]]).

## Signing out every device from the web

The Sign Out All Devices button asks in the shared confirm dialog, with the mobile sheet's title and body from the parity copy, then posts to the endpoint described in [[identity-and-access#Sessions, cookies and bearer tokens#Signing out every browser]].

The endpoint redirects to the public home page signed out, and the page runs the same cache purge as account deletion, under the same guard: a refusal, such as a failed CSRF check or a rate limit, redirects back with the reader still signed in, so the page purges only when the returned page no longer names the same user. The endpoint takes no account id, so the button can only ever end the reader's own sessions.

## Changing the address from the web

The Profile page's Address link opens `GET /users/address/edit`, which renders the registration page in change-address mode for a registered reader and sends anyone else to first-time registration.

[[app/controllers/users/addresses_controller.rb#AddressesController#edit]] passes `change_address` and the current address as plain text, joined from only the parts the stored address has, so a street-only address shows no empty commas. In that mode [[app/frontend/pages/SwayRegistration.tsx#SwayRegistration]] shows the current address and the mobile edit copy, cancels back to Profile instead of signing out, and asks for the switch confirmation before it posts. It records no registration funnel step, because the reader registered long ago and counting the visit would inflate the admin funnel. The post goes to `POST /sway_registration`, the same endpoint mobile uses, so the switch keeps its confirmation, cooldown and audit row ([[identity-and-access#A user holds one address]]).

The switch's refusals used to redirect to the registration index, and the index sends a registered reader to the feed, so the message was lost. [[app/controllers/sway_registration_controller.rb#SwayRegistrationController#address_switch_return_path]] sends an Inertia request from a registered reader that carries the `change_address` marker back to the change-address page instead, for every outcome of an address switch that does not complete: confirmation required, cooldown, geocoding unavailable, switch unavailable, no representatives and address not located. The address-not-located outcome also reaches a registered reader whose stored address was never located, because saving a still-unlocated address replaces it without a switch; that path goes back to the change-address page too. The page adds that marker to its post only in change-address mode. Being registered is not enough on its own, because a first-time reader's first unlocated save completes registration: without the marker, that reader's second save from the registration page would land on the change-address page, with its copy, a Cancel that keeps them signed in, and no further funnel steps. The controller also picks the target once, before it writes anything, so the first save itself never counts as registered. First-time registration and the JSON answers mobile reads keep their old targets.
