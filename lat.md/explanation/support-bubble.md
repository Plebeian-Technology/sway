---
lat:
  mode: explanation
---
# Support bubble placement

The Support bubble lets voters schedule a live privacy walkthrough from every web screen in AuthLayout. It stays fixed in the bottom-right corner outside page transitions to remain responsive at all times.

## Why the support bubble exists

The public privacy policy at about.sway.vote promises voters a Support bubble in the bottom-right corner of the web app to schedule a privacy walkthrough. [[app/frontend/components/support/SupportBubble.tsx#SupportBubble]] fulfills that promise.

Clicking the trigger opens a dialog titled "Request a privacy walkthrough". The dialog explains that Sway conducts walkthroughs over video chat to inspect the app, the database, and the voter's own account records with their permission. The action link connects to `mailto:info@sway.vote?subject=Privacy%20walkthrough%20request`. Because `sway.vote` email addresses operate as catch-alls, scheduling directly over mailto avoids introducing extra server endpoints or external appointment booking scripts.

## Why the bubble sits outside PageBodySlot

Inertia navigations mark the active [[app/frontend/components/layouts/PageBodySlot.tsx#PageBodySlot]] element with `inert` while requests are in flight. Placing SupportBubble outside that container keeps the trigger responsive throughout transitions.

[[app/frontend/components/layouts/AuthLayout.tsx#AuthLayout]] renders SupportBubble as a direct child of `OfflineContext.Provider`, adjacent to the main application grid. If the trigger sat inside PageBodySlot, voters navigating between bills or legislator profiles would find the bubble temporarily unresponsive. Sitting outside the page body prevents the browser from trapping or dropping clicks during background Inertia visits.

## Overlay layering and touch ergonomics

The bubble uses fixed positioning at `z-40` with safe area offsets to remain reachable across viewport sizes. It sits below modal sheets and dialogs while meeting accessibility touch target minimums.

Tailwind classes `fixed right-4 bottom-[max(1rem,env(safe-area-inset-bottom))]` anchor the trigger above the mobile home indicator. Setting the z-index to `z-40` leaves `z-50` overlays—including the Radix dialog backdrop and navigation drawer—free to occlude the trigger when open. Minimum dimensions of `min-h-11 min-w-11` (44 by 44 CSS pixels) satisfy touch target guidelines.

## Universal availability across auth states

Privacy walkthroughs are available to prospective voters and registered users alike. The layout renders the trigger unconditionally for both authenticated accounts and guest visitors.

The component performs no authentication checks. A guest evaluating Sway's privacy model before creating an account can request a database walkthrough just as easily as an enrolled voter.
