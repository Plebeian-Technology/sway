# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What is Sway

Sway is a civic engagement platform where users vote on the same legislation as their elected representatives, enabling accountability tracking. Built as a Rails + React monolith using Inertia.js for server-driven rendering.

Supported locales: Baltimore City (MD), State of Maryland, US Congress.

## Tech Stack

- **Backend:** Rails 8.1 / Ruby 4.0.1 / SQLite (WAL mode)
- **Frontend:** React 19 / TypeScript 5.9 / Vite 7.3 / MUI 7
- **Bridge:** Inertia Rails (server-driven React props, no client-side routing)
- **Jobs:** Solid Queue with separate SQLite database
- **Auth:** WebAuthn (passkeys) + Twilio SMS verification
- **Real-time:** ActionCable WebSockets for score sync
- **Deployment:** Kamal, Docker (Alpine), Caddy reverse proxy, Cloudflare tunnel

## Development Commands

```bash
# Initial setup
bundle install && npm install
bundle exec rails db:create db:migrate db:schema:load db:seed

# SSL certs (required - app runs HTTPS only)
brew install mkcert nss && mkcert -install && mkcert localhost
mkdir -p config/ssl && mv localhost.pem config/ssl/cert.pem && mv localhost-key.pem config/ssl/key.pem

# Run Rails server (terminal 1)
bin/rails server -b 'ssl://localhost:3333?key=config/ssl/key.pem&cert=config/ssl/cert.pem&verify_mode=none'

# Run Vite dev server (terminal 2)
./bin/vite dev

# Run background jobs (terminal 3)
bin/jobs

# Browse at https://localhost:3333
```

### Testing & Linting

```bash
bundle exec rspec                    # Run all backend tests
bundle exec rspec spec/models/       # Run model tests only
bundle exec rspec spec/path_spec.rb  # Run a single test file
bundle exec rspec spec/path_spec.rb:42  # Run a single example by line

npx eslint app/frontend/             # Lint TypeScript/React
npx tsc                              # TypeScript type checking
npm run prettier                     # Format all files (JS 4-space, Ruby 2-space)
```

## Architecture

### Inertia.js Pattern (Critical)

Sway uses Inertia.js - Rails controllers render React pages by passing props, not JSON APIs. No client-side router exists.

- Controllers call `render inertia: "PageName", props: { ... }` instead of returning JSON
- React pages receive data as props, not via fetch/axios
- Form submissions use `useInertiaForm` hook, not direct API calls
- Score updates use a hybrid: ActionCable push triggers `router.reload({ only: [...] })` partial reloads, with `usePoll(15000)` as fallback
- All sync reloads use `preserveScroll: true`

### Backend Structure

- `app/controllers/` - Rails controllers (render Inertia props to React pages)
- `app/models/` - ActiveRecord models (User, Bill, Legislator, BillScore, UserVote, etc.)
- `app/services/` - Service objects (SwayRegistrationService, ScoreUpdaterService, InfluenceService)
- `app/jobs/` - Solid Queue background jobs (score updates, notifications, SMS delivery)
- `app/channels/` - ActionCable channels (ScoreChannel for real-time score sync)

### Frontend Structure

- `app/frontend/pages/` - Inertia page components (top-level, receive server props)
- `app/frontend/components/` - Reusable React components
- `app/frontend/hooks/` - Custom hooks (useScoreSubscription, etc.)
- `app/frontend/channels/` - ActionCable consumer setup
- `app/frontend/sway_constants/` - App constants
- `app/frontend/sway_utils/` - Utility functions

### Key Domain Concepts

- **SwayLocale** - A geographic jurisdiction (city/state/federal) with its own bills, legislators, and districts
- **BillScore** - Aggregated voting data per bill (district-level and locale-level)
- **UserVote** - A user's vote on a bill, compared against their legislator's vote
- **District** - Geographic area with GeoJSON boundaries, links users to legislators
- **Bill of the Week** - Admin-curated featured legislation with scheduled notifications

### Registration Flow

Uses a state machine (`state_machines-activerecord`): `pending` → `processing` → `completed` / `failed`. Registration is async because it involves geocoding addresses and assigning legislators via external APIs.

## Code Style

- **Ruby:** Double quotes, 2-space indent, RuboCop with Shopify/Performance presets
- **TypeScript/JS:** Double quotes, 4-space indent, trailing commas, semicolons
- **Commits:** [conventional-changelog format](https://github.com/conventional-changelog/conventional-changelog-angular/blob/master/convention.md)
- **Type checking:** Sorbet for Ruby (with Tapioca-generated RBI files)

## CI/CD

GitHub Actions runs on every push: RSpec, ESLint, TypeScript type checking, CodeQL security analysis. All checks must pass before merge.

## Main Branch

The primary branch is `padawan` (not `main`).
