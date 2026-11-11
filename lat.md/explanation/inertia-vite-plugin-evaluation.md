---
lat:
  mode: explanation
---
# Inertia Vite Plugin Evaluation

Evaluation of the @inertiajs/vite plugin migration against Sway's Rails and Vite architecture, concluding that no functional driver justifies adoption.

## Background and Scope Constraints

Server-side rendering is permanently out of scope for Sway, which limits the potential architectural impact of the @inertiajs/vite plugin.

Server-side rendering (SSR) is excluded from Sway's architectural scope. Sway operates as a client-rendered monolith deployed via Kamal Docker containers to single-board hardware (such as a Raspberry Pi) and container environments. In this architecture, Inertia pages are sent to the client as lightweight JSON data payloads inside an initial HTML shell, and the React tree hydrates and renders entirely in the client browser. Because SSR is out of scope, the primary capability that `@inertiajs/vite` was built to provide—namely SSR build targets, node server entrypoints, and bundle splitting for SSR—offers zero benefit to the Sway deployment.

## Page Resolution Simplicity

Page component resolution is already cleanly isolated in a stable 23-line module without external plugin dependencies.

The application delegates page resolution to `app/frontend/pageResolver.ts`. This module contains 23 lines of standard TypeScript using Vite's native `import.meta.glob` to map server page names to component loader functions under `app/frontend/pages/`. It handles default page fallbacks and missing component errors predictably. The implementation has remained unchanged and maintenance-free across major frontend upgrades, demonstrating that replacing it with plugin-level magic would eliminate fewer than 30 lines of code while introducing external configuration overhead.

## Phase A Evaluation: Plugin Coexistence and HMR Routing

Introducing @inertiajs/vite alongside rails-vite-plugin introduces configuration duplication and risk to Caddy reverse-proxy HMR websocket routing.

Sway's `vite.config.ts` relies on `rails-vite-plugin` to coordinate asset paths between Rails tag helpers and the Vite dev server. In development, TLS terminates at Caddy on port 3333, and Caddy reverse-proxies asset and WebSocket traffic to Vite on port 3036. Hot Module Replacement (HMR) specifically routes over WebSocket through the path `/vite-hmr`. The `@inertiajs/vite` plugin is tailored primarily for Laravel Vite conventions and assumes standard Laravel entrypoints. Layering it on top of `rails-vite-plugin` risks conflicting with asset manifest generation and HMR websocket dispatch without adding any new capability.

## Phase B Evaluation: Layout Selection Architecture

A centralized two-line layout check in the entrypoint provides cleaner maintenance than distributing per-page layout declarations across seventeen files.

In `app/frontend/entrypoints/application.tsx`, layout selection is determined by checking page names against a 2-element array `NO_AUTH_LAYOUTS = ["home", "swayregistration"]`. Pages in this list receive `NoAuthLayout`, while all other pages automatically default to `AuthLayout`. Any individual page can still override its layout explicitly via `page.layout`. Migrating layout selection to individual page components would require adding imports and `Page.layout = AuthLayout` declarations across 17+ separate page files, along with updating corresponding test mocks. The centralized default keeps pages focused on their unique rendering logic while preventing accidental missing-chrome regressions on new pages.

## Phase C Evaluation: Provider Tree Wrapping

The application entrypoint wraps the root React tree and handles asynchronous Sentry error boundary initialization in twelve lines.

The `setup()` function in `app/frontend/entrypoints/application.tsx` mounts the React application in 12 lines. It dynamically imports `@sentry/react` to optimize initial script evaluation and wraps `<InertiaApp>` in `<SentryErrorBoundary>` and `<App>`. The `withApp` helper from `@inertiajs/vite` is a static callback designed for standard single-page app wrappers and does not provide superior handling for asynchronous error boundary initialization. Replacing `setup()` with `withApp` provides no tangible simplification.

## Resolution of the Readiness Constraint

Formal evaluation confirms that no second functional reason exists for adopting @inertiajs/vite, satisfying the decision gate to retire the migration.

The evaluation established a strict readiness constraint: migration would activate only if a second functional reason emerged beyond cosmetic convention alignment. The architectural evaluation confirms that:
1. SSR remains permanently out of scope;
2. Page resolution in `app/frontend/pageResolver.ts` is 23 lines, robust, and stable;
3. Centralized layout selection is superior to touching 17 page files;
4. Root provider setup is concise and handles dynamic Sentry loading cleanly;
5. Adding the plugin risks regressions in Caddy `/vite-hmr` WebSocket routing and `rails-vite-plugin` manifest coordination.

Because no functional driver exists, the evaluation is complete and the migration is formally rejected.
