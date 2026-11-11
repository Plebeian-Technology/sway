---
lat:
  mode: explanation
---

# Public marketing and meta pages

`MarketingController` and `MetaController` render public, unauthenticated pages accessible to carrier reviewers, mobile store reviewers, and search crawlers without requiring account creation.

These controllers host pages outside the main application authentication perimeter, ensuring reviewers and external visitors can access verification, legal, and licensing documents.

## Why MarketingController sms, privacy and terms exist

Regulatory and carrier verification for Twilio A2P 10DLC requires public access to SMS opt-in terms and disclosures without requiring an account.

`/sms`, `/privacy`, and `/terms` are public disclosure documents. They exist for carrier reviewers who have no Sway account and cannot verify an SMS number during review. `/sms` reproduces the consent checkbox and disclosures shown at `/notifications` so reviewers see the exact text submitted for approval.

## Why /sms, /privacy and /terms are Inertia pages under a second, minimal entrypoint

Public compliance pages render through a lightweight Inertia entrypoint to isolate static legal disclosures from authenticated bundle errors.

The pages render through `Pages::SMS`, `Pages::PRIVACY`, and `Pages::TERMS` (`app/frontend/pages/public/*.tsx`) using a dedicated `public.tsx` entrypoint rather than the standard `application.tsx` bundle. The main bundle includes complex subsystems such as service-worker registration, ActiveStorage, scroll polyfills, flash toasts, and layout wrappers; runtime errors in those systems must not disrupt carrier compliance reviews.

`MarketingController` declares `layout "public"` (`app/views/layouts/public.html.erb`), emitting `vite_typescript_tag 'public.tsx'`. The `app/frontend/entrypoints/public.tsx` entrypoint uses a minimal `createInertiaApp` configuration scoped to `import.meta.glob("../pages/public/**/*.tsx")`. It includes Tailwind styling via `application.css`, Sentry initialization, and error boundaries while omitting unnecessary authenticated dependencies.

The three page controller actions use explicit routes such as `get "sms", to: "marketing#sms"` rather than Inertia route helpers because the standard helper bypasses `ApplicationController` and skips layout overrides. `#mobile_download` explicitly passes `layout: "application"`, overriding the controller-level default layout.

Because `app/frontend/pages/public/*.tsx` lives under a path containing `public`, unanchored linter patterns can inadvertently skip these files. Anchoring rules to root `/public/` prevents compliance pages from escaping automated linting.

## Why /download is routed unless Rails.env.production?

The mobile download marketing route is disabled in production environments until store listings and production assets are finalized.

The `/download` endpoint is withheld from production until launch prerequisites are complete, including a real App Store identifier. Because no internal application links target `/download`, disabling the route does not impact existing user navigation. Controller actions, templates, and specs remain intact, allowing production activation via route configuration.

## Why MarketingController.mobile_download renders plain ERB, not Inertia

The mobile download landing page renders as plain ERB templates to remain accessible to web crawlers and clients without JavaScript.

Rendering `/download` via server-rendered ERB ensures mobile store reviewers and search indexing crawlers access download badges and links without JavaScript execution. The template resides at `app/views/pages/mobile_download.html.erb` alongside other public views.

## Why the Apple App Store id is a placeholder

The App Store identifier uses a temporary configuration placeholder pending final application record creation in App Store Connect.

`@apple_app_store_id` resolves from `Sway::Settings.mobile.apple_app_store_id`. The permanent application identifier becomes available once the application entry is created in App Store Connect, requiring placeholder replacement prior to mobile release as documented in [[lat.md/how-to/submit-the-mobile-app.md|submit-the-mobile-app.md]].

## Why MetaController's pages skip the sign-in and API-route checks

Version and licensing endpoints bypass authentication checks to provide public visibility into application build information.

`GET /version` and `GET /licenses` bypass `authenticate_sway_user!` and `is_api_request_and_is_route_api_accessible?` checks to ensure open public access.

`/version` provides mobile-friendly rendering of release metadata matching the `release` prop documented in [[docs/explanation/release-git-fallback-and-caching.md|release-git-fallback-and-caching.md]], which the logo tooltip displays elsewhere in the application.

`/licenses` attributes open-source frontend dependencies, with scope and gem exclusions detailed in [[docs/explanation/oss-licenses-page-scope.md|oss-licenses-page-scope.md]].

