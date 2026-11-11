---
mode: explanation
summary: "Why MarketingController renders /download as plain ERB but /sms, /privacy and /terms as Inertia pages under a second minimal entrypoint, why the App Store id is a placeholder until launch, why /download is kept out of production, why /sms, /privacy and /terms exist for carrier review, and why MetaController's /version and /licenses pages are public with no sign-in check."
status: agent-extracted
related: [docs/explanation/oss-licenses-page-scope.md, docs/explanation/release-git-fallback-and-caching.md]
---

<!-- vale Vale.Spelling = NO -->

# `MarketingController` and `MetaController`: public, unauthenticated pages

## Why `MarketingController#sms`, `#privacy` and `#terms` exist

Twilio A2P 10DLC carrier reviewers need a public page that shows the consent
copy — the screen where a user consents to receive text messages. That screen
is the SMS panel on `/notifications`, which sits behind
`authenticate_sway_user!`. A carrier reviewer has no Sway account and won't
create one, and gating the page
behind SMS verification doesn't help either, since verifying a number means
sending an SMS — the very thing under review.

`/sms`, `/privacy` and `/terms` are disclosure documents, not the opt-in
itself: the working toggle stays at `/notifications` behind auth. They exist
for TCR/carrier reviewers the same reason `/download` exists for App Store
reviewers — reachable with no account and no session cookie.

`/sms` reproduces the consent checkbox as a disabled, inert copy (it cannot
embed a screenshot) using the exact label and disclosure text shown at
`/notifications`, so the copy a reviewer reads matches what was submitted to
Twilio. `/privacy` and `/terms` are the published privacy policy and terms of service.

## Why `/sms`, `/privacy` and `/terms` are Inertia pages under a second, minimal entrypoint

Unlike `/download`, these three do not need to work with JavaScript
disabled. They render through `Pages::SMS`, `Pages::PRIVACY` and
`Pages::TERMS` (`app/frontend/pages/public/*.tsx`), but not through the
authenticated app's `application.tsx` entrypoint: that bundle is large,
pulls in things a static disclosure page has no use for (PWA/service-worker
registration, ActiveStorage, the scroll-restoration polyfill, flash toasts,
`AuthLayout`/`NoAuthLayout`), and a crash inside any of that would take the
disclosure page down with it — which is exactly the failure mode a carrier
reviewer must not hit.

So `MarketingController` sets `layout "public"`
(`app/views/layouts/public.html.erb`), which emits
`vite_typescript_tag 'public.tsx'` instead of `'application.tsx'`.
`app/frontend/entrypoints/public.tsx` is a second, minimal
`createInertiaApp` bootstrap scoped to
`import.meta.glob("../pages/public/**/*.tsx")`, so it cannot resolve — and
therefore cannot accidentally pull in — any authenticated page. It keeps
Tailwind (via `application.css`), Sentry init, and the error-boundary
fallback; it drops everything the paragraph above lists, including the
`AuthLayout`/`NoAuthLayout` selection, replacing it with a small inline
shell that only removes the `#application-loading` spinner.

The three page controller actions use explicit `get "sms", to:
"marketing#sms"`-style routes (not inertia_rails' own `inertia` route
helper) because that helper renders through InertiaRails' own controller,
which does not inherit from `ApplicationController` — so the
`skip_before_action` calls and `layout "public"` would not apply.

`#mobile_download` is unaffected by the class-level `layout "public"`: its
own `render template: "pages/mobile_download", layout: "application"` call
passes an explicit `layout:`, which overrides the class default.

`app/frontend/pages/public/*.tsx` sits under a directory literally named
`public`, and both `.oxlintrc.json` and `.oxfmtrc.json` carry an unanchored
`"public/"` ignore pattern meant for the root-level Rails `public/` assets
directory. That pattern matches any path with a `public/` segment, so
`oxlint`/`pnpm lint` and `oxfmt`/`pnpm fmt:check` silently skip every file
here — `oxlint app/frontend/pages/public/Sms.tsx` reports "No files found to
lint" rather than an error. These files were verified by linting and
formatting copies placed at a sibling path outside `public/`, but that's a
workaround, not a fix: anchoring both patterns to `/public/` (root only)
would close the gap for this directory and any future one.

## Why `/download` is routed `unless Rails.env.production?`

`/download` is kept out of production until it is ready to launch — the App
Store badge points at a placeholder id until the app record exists. Nothing in the app links to
`/download`, so hiding it doesn't break any in-app flow. The controller
action, template and request spec are left in place; restoring it in
production is a one-line route change.

## Why `MarketingController#mobile_download` renders plain ERB, not Inertia

The public marketing page for the mobile app (mounted at `/download`)
renders a plain ERB template, not an Inertia page, so it works with no
JavaScript at all: app-store reviewers and search crawlers that do not run
JavaScript still see it, and the install badges are ordinary links they
can follow.

The template lives at `app/views/pages/mobile_download.html.erb`, beside
the other public pages instead of in a folder named after this
controller, so the marketing pages stay together.

## Why the Apple App Store id is a placeholder

`@apple_app_store_id` reads `Sway::Settings.mobile.apple_app_store_id`. The
real App Store id only exists once the app record is created in App Store
Connect, so a placeholder ships in the link until then. Replacing it
is part of submitting the app (see `lat.md/how-to/submit-the-mobile-app.md`).

## Why `MetaController`'s pages skip the sign-in and API-route checks

`GET /version` and `GET /licenses` are both public on purpose — anyone
should be able to see what a civic app is running. The sign-in check
(`authenticate_sway_user!`) and the API-route check
(`is_api_request_and_is_route_api_accessible?`) are skipped here, the same
way `MarketingController` skips them.

`/version` is the linkable, mobile-friendly view of the same release
metadata that rides along on every page as the shared `release` prop (see
[release-git-fallback-and-caching.md](release-git-fallback-and-caching.md)),
which the logo tooltip shows elsewhere in the app.

`/licenses` gives credit for the open-source code Sway's frontend bundle
depends on — see
[oss-licenses-page-scope.md](oss-licenses-page-scope.md) for what it lists
and why Ruby gems are excluded.
