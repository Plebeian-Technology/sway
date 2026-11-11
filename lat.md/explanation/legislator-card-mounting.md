---
lat:
  mode: explanation
---

# When a legislator card is mounted

The representatives list mounts the first eight cards with the page and holds a sized placeholder for every card after them, so a long roster is spread over several commits instead of one.

A Firefox profile of one visit to `/legislators` recorded a single uninterrupted 1,021ms block of main-thread work, spread across arena allocation, object initialisation and property-map lookups rather than concentrated in any one function. Across roughly 28,600 samples in three captures, none landed in code under `app/frontend`. The cost is the number of components created in one commit, and React cannot yield to the browser part-way through a commit, so nothing on the page responds while it runs.

Charts are not what makes a card expensive. [[app/frontend/components/legislators/LegislatorCard.tsx#LegislatorCard]] keeps `LegislatorChartsPanel` behind a per-card toggle that starts closed, so the cost of a card is its photo, its three score tiles and its two controls.

## One panel holds both score views

`tab !== "history"` guards a single `<TabsContent key="scores" value={tab}>` whose `value` follows the selected tab and whose `mode` is computed from it, so Current and Lifetime are one list of cards rather than two.

Radix discards the panel that is not showing. Two parallel panels gave each score view its own `LegislatorCard`, so flipping between Current and Lifetime destroyed the card and everything it was holding — a card with its voter-agreement charts open snapped shut on the flip. One panel with a fixed key keeps each card the same live component across the flip.

## Mounting is decided by a client-side observer

[[app/frontend/components/MountWhenNear.tsx#MountWhenNear]] renders an `aria-hidden` placeholder until an `IntersectionObserver` reports that placeholder within 800px of the viewport, then renders its children and disconnects.

Inertia's `WhenVisible` was the rejected alternative. It exists to fetch a deferred server prop when an element scrolls into view, and the roster here is already in the props — using it would issue one request per card for data the browser holds. Nothing about this decision reaches the server.

The 800px margin is what makes the mount finish before the reader arrives. The observer fires while the placeholder is still that far below the fold, which is more than a phone screen's height, so the card has been committed by the time it would have been read.

A browser with no `IntersectionObserver` renders the children on the first commit. That is the old behaviour rather than a broken page, and it is also what a jsdom test sees unless the test supplies its own stub.

## The threshold is a count of cards

`ABOVE_FOLD_COUNT` in [[app/frontend/pages/Legislators.tsx#Legislators]] is eight cards, not a pixel height.

A pixel budget would have to be measured against a viewport the component cannot see at render time, and the answer would differ between a 320px phone and a desktop window while the markup is identical. A count is decided once, is the same on every device, and errs toward mounting more than the first screenful — eight cards is several screens on a phone, so the reader never meets a placeholder that has not already had time to resolve.

Eight also leaves the ordinary reader's page unchanged. `LegislatorsController#index` scopes the roster to the reader's own representatives, which is a handful in each of the three jurisdictions, so the deferral only takes effect on a roster larger than any of them — an account holding several jurisdictions' worth of assignments, or a locale whose seats are all at-large.

The placeholder's `min-h-96` is a scroll-height estimate, not a promise. A card is taller than that on a narrow screen and shorter on a wide one; the class exists so a page of placeholders has a plausible scrollbar, and the height corrects itself as each card mounts.
