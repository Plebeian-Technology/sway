---
lat:
  mode: explanation
---

# Entrypoint bootstrap notes

Notes on two decisions in `app/frontend/entrypoints/application.tsx` that are not obvious from the code alone.

## Why the stylesheet import comes first

Stylesheet first so the bundled `<link rel="stylesheet">` is in the head before any DOM-mutating code runs.

This prevents Firefox's "Layout was forced before the page was fully loaded" warning that triggers when JS schedules style recalc / queues classList changes while the CSS is still being parsed.

## Why "passkey" and "registration" were removed from NO_AUTH_LAYOUTS

"passkey" and "registration" used to be listed here, but both were dead entries.

"passkey" and "registration" used to be listed here, but both were dead entries: there's no Inertia "Passkey" page (sign-in flows through PasskeyPanel inside the Home layouts instead), and there's no `pages/Registration.tsx` (the server renders "SwayRegistration" instead). So `pageName.toLowerCase()` could never match either one.

## Why the entrypoint bails out when the document carries no Inertia payload

`app/views/layouts/application.html.erb` always emits `vite_typescript_tag 'application.tsx'`, so every page rendered in that layout loads this entrypoint — including pages that are not Inertia pages at all.

`MarketingController` renders plain ERB templates in that layout, and a plain ERB template carries no Inertia page payload.

Without a guard, `createInertiaApp` runs anyway, reaches `resolveComponent(initialPage.component, initialPage)` inside `@inertiajs/react`, and throws `TypeError: can't access property "component", v is null`. That was reaching production: a Sentry error raised from `https://app.sway.vote/download`.

The visible symptom was worse than the log line. The layout renders `<div id="application-loading">` with a spinner, and only `App.tsx` removes it once the React tree mounts. When `createInertiaApp` throws, nothing ever mounts, so the spinner stays on screen underneath the page content forever and the page reads as broken rather than finished.

The guard tests for `[data-page]`, which matches both markup shapes the gem can emit: the `<script data-page="app" type="application/json">` element used when `use_script_element_for_initial_page` is on (the setting this app uses), and the `<div id="app" data-page="...">` form used when it is off. On the non-Inertia path the entrypoint removes the spinner itself and still registers the service worker, so a plain ERB page renders exactly as authored with the stylesheet and PWA support intact.

## Why no entrypoint defines a React component inline

`application.tsx` imports its shell from `app/frontend/App.tsx`, and `public.tsx` imports its own from `app/frontend/PublicApp.tsx`. Neither declares a component in the entrypoint file. That is a requirement, not a preference.

`@vitejs/plugin-react` instruments any module that declares a React component for Fast Refresh. An entrypoint that declares one is pulled into the Fast Refresh graph, and in dev the browser then loads it under two URLs: once as the plain script the layout emits, and once with Vite's cache-busting `?t=<timestamp>` query. Two URLs are two entries in the browser's module registry, so the module body runs twice. For an entrypoint that means two `DOMContentLoaded` listeners, two `createInertiaApp` calls, and two `createRoot` calls on the same `#app` element:

```
You are calling ReactDOMClient.createRoot() on a container that has
already been passed to createRoot() before.
```

`public.tsx` shipped this way briefly. It declared a `PublicShell` component inline, and oxlint's `react(only-export-components)` reported exactly the right diagnosis — "Fast refresh only works when a file has exports. Move your component(s) to a separate file." The warning was suppressed with an `oxlint-disable` line rather than acted on, and the double mount reached the browser. Moving the component to its own file removed both the warning and the bug, and the suppression comment came out with it.

The symptom is easy to misread as an Inertia or a layout problem. The quickest confirmation is a module-level `console.log` of `import.meta.url` in the entrypoint: if it prints twice with two different URLs, one bare and one carrying `?t=`, this is the cause.
