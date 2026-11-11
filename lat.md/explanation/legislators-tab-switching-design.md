---
lat:
  mode: explanation
---

# Why Legislators.tsx switches tabs without a server round trip

`app/frontend/pages/Legislators.tsx` switches its Current term, Lifetime, and History tabs entirely client-side without a round trip because both scores arrive in the initial page payload.

The chosen tab is also mirrored in `?tab=` via `history.replaceState` so that it persists across locale switches. When `?tab=history` is present, the server provides history data up front. `window.history.state` is preserved so Inertia can restore page snapshots during back and forward navigation.

This design differs from the Notifications page (`app/frontend/pages/Notifications.tsx`), which requests updates from the server on each tab change.

## The Current | Lifetime toggle and why an open accordion used to close on flip

Flipping between Current and Lifetime tabs preserves expanded cards because both views render inside a single panel rather than separate unmounting panels.

By default the page displays tallies for the term a legislator is currently serving, while switching to Lifetime aggregates tallies across all recorded terms. Rendering both views in a single panel with a stable key prevents Radix from unmounting child accordions when switching views.

The term year range shown under the tabs uses an en dash without extra text. Because legislators in a locale share an election cycle, the first representative's term represents the page roster.

## LegislatorCard.tsx's mode and historyEntry props

`mode` (`"current"` or `"lifetime"`) selects the score scope rendered by `LegislatorCard`, while `historyEntry` indicates a frozen history view.

When `historyEntry` is provided, the card renders frozen historical tallies with an "Ended" badge and suppresses the interactive charts toggle.

## LegislatorChartsPanel's mode prop and chart list

`LegislatorChartsPanel` renders agreement charts for a legislator across user agreement, district agreement, and locale agreement scopes.

The container presents up to three charts:
1. User agreement with the legislator (`user_legislator_score`)
2. District agreement with the legislator (`legislator_district_score`, omitted for at-large representatives)
3. Locale agreement with the legislator (`legislator_locale_score`)

`mode` determines whether captions reflect current term scores or lifetime scores. When locale information is unavailable, the component falls back to neutral agreement labels without a jurisdiction prefix.

## Why districtLabel checks typeof === "number"

`district.number` can be missing at runtime, so checking `typeof === "number"` avoids rendering "District undefined" when the object exists without a number.

Checking `typeof === "number"` explicitly distinguishes null and undefined values from valid numeric district values.

## Mobile: LegislatorsListScreen's term year range

The term year range displayed under the control derives from the first legislator's election cycle, representing the entire locale.

If the first legislator has no active term, the segment displays the year range instead of "Current term".

## Mobile: LegislatorDetailScreen's chart list

`LegislatorDetailScreen` renders user, district, and locale agreement charts matching the web layout, omitting district charts for at-large officials.

For at-large officials, district totals equal locale totals, so the district chart is omitted.

The header omits party affiliation on purpose and sets explicit inline dimensions (`width: 96, height: 112`) on the avatar and row container so NativeWind cannot collapse the avatar to zero width on physical devices. Because the database stores no street address for a legislator, the contact section uses the district and region label as a stand-in and links it to a Google Maps search query.
