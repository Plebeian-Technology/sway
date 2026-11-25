---
lat:
  mode: reference
---
# Delivery surfaces

The same models are read through five surfaces. Which one a controller action serves determines how it renders, how it authenticates, and which keys it may not rename.

## Inertia pages

The primary surface: a controller renders `render inertia: "PageName", props: {...}` and the matching component under `app/frontend/pages/` receives those props.

- User-facing — `Home`, `Feed`, `Bill`, `Bills`, `BillOfTheMonth`, `Legislator`, `Legislators`, `Influence`, `Notifications`, `SwayRegistration`, `PasskeyManagement`, `ApiKeys`, `Version`, `Licenses`
- Organizations — `Organization`, `Organizations`, and the four screens under `pages/organizations/`
- Admin — `admin/Index`, `admin/Categories`, `admin/LlmSettings`, `admin/Locales`, `admin/PipelineRuns/Index`, `admin/UserAddressChanges`, and `BillCreatorPage`, which is the Bill Creator
- Address registration — `SwayRegistration` provides address autocomplete via Nominatim and maps components into registration form state


## Dual-rendered JSON

Controllers including [[app/controllers/concerns/mobile_format_negotiation.rb#MobileFormatNegotiation]] answer one action as either an Inertia page or JSON, decided by `mobile_api_request?`, across `scope "api"` routes and dual-rendered top-level routes.

- `render_inertia_or_json(page:, props:)` — resolves the props and renders JSON for a mobile request, Inertia otherwise
- `redirect_or_json(path, flash_message:)` — returns `{redirect:, flash:}` for a mobile request, a real redirect otherwise
- [[app/controllers/concerns/mobile_format_negotiation.rb#MobileFormatNegotiation#respond_after_write]]`(path, back:, status:, json:, notice:, alert:, errors:)` — answers an admin write: for a mobile request, `json` with 200, or the 422 `validation_failed` error envelope when `errors` or `alert` is present; otherwise a redirect (or redirect back) carrying the status, flash and Inertia errors
- Read paths (`scope "api"`) — `bills`, `bill_of_the_month`, `bill_scores`, `bill_score_districts`, `districts`, `influence`, `legislators`, `legislator_votes`, `organizations`, `organization_bill_positions`, `sway_locales`
- Top-level `/feed` — [[app/controllers/feed_controller.rb#FeedController#index]] branches on `mobile_api_request?` to serve mobile JSON via `render_inertia_or_json` (without `newest_keys`) and Inertia scroll props otherwise, with no `scope "api"` duplicate
- Admin write paths — `bills`, `bill_of_the_month_schedule`, `legislator_votes`, `organizations`, `organization_bill_positions`, under `scope "api"` then `scope "admin"`

## The /api/v1 mobile API

A namespace for mobile flows under [[app/controllers/api/v1/base_controller.rb#BaseController]]. Account identity requires an API token; public access and the telemetry exception follow [[identity-and-access#Sessions, cookies and bearer tokens]].

- `sessions` — passkey challenge, discoverable (identity-blind) challenge, callback, `revoke_all`
- `registrations` — first-time passkey enrollment, consuming an SMS-verified token
- `passkeys` — adding a further discoverable passkey to a signed-in account
- `phone_verification` — SMS code request and verify; `/verify` issues a one-time `SmsVerificationToken`
- `devices` — push-token upsert and per-device revocation
- `bootstrap` — the single read performed at app launch; delivers the featured bill under the single `bill_of_the_month` key
- `notification_preferences` — four key-scoped toggles in [[mobile/src/hooks/useNotificationPrefs.ts#useNotificationPrefs]] matching `NotificationPreference::KEYS` (the index returns `botm_announcement` only, while `toggle` updates optimistically and reverts on failure) plus organization defaults

## ERB and well-known

A small set of responses render without the React bundle, either because they must work without it or because another system reads them.

- `/download` — the mobile marketing page, which must work with no bundle
- `/.well-known/apple-app-site-association` and `/.well-known/assetlinks.json` — associated-domain files, served from both `sway.vote` and `app.sway.vote`; includes `/bill_of_the_month` and the retired `/bill_of_the_week` universal link paths
- `/.well-known/webauthn` — relying-party metadata
- `/sitemap.xml`, `/version`, `/licenses` — public and unauthenticated

## ActionCable channels

Three channels push, and in all three cases the browser answers by reloading props rather than by applying the payload.

- `ScoreChannel` — broadcast by `ScoreUpdaterService` after a recompute; consumed by [[app/frontend/hooks/useScoreSubscription.ts#useScoreSubscription]]
- `PipelineRunChannel` — broadcast by `PipelineRunBroadcast` during a run; consumed by `usePipelineRunSubscription`
- [[app/channels/feed_channel.rb#FeedChannel]] — broadcast by [[app/services/feed_broadcaster.rb#FeedBroadcaster]] via [[app/jobs/feed_update_broadcast_job.rb#FeedUpdateBroadcastJob]]; consumed by [[app/frontend/hooks/useFeedSubscription.ts#useFeedSubscription]]
