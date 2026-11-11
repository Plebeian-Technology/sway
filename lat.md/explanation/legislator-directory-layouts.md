---
lat:
  mode: explanation
---

# Legislator directory layouts

Why the default, monochrome, service manual, and Swiss grid layouts carry distinct visual identities for representative directories.

## Legislator directory layout selection

Layout selection dispatches the directory view by active theme while isolating page state management.

Theme-driven resolution relies on `legislatorsLayoutFor(themeId)` in `app/frontend/components/legislators/layouts/index.ts`. Standard themes (`sway`, `banner`, `ballot`, `cornerstore`) and unrecognized theme identifiers resolve synchronously to `DefaultLegislatorsLayout`. The three readability themes (`monochrome`, `service-manual`, `swiss-grid`) resolve through dynamic imports wrapped in `React.lazy`, enabling deferred bundle loading. An export alias `legislatorListLayoutFor` preserves architectural consistency with bill list layouts.

## Legislators page container

The container coordinates data subscriptions and URL navigation parameters without coupling to layout markup.

`Legislators.tsx` maintains polling intervals and WebSocket notifications through the shared module constant `POLLING_PROPS = ["legislators"]`. The page coordinates tab state with URL parameters, manages locale switching, and triggers demand-driven history retrieval. Presentation delegates entirely to the resolved layout rendered inside `React.Suspense` with `DefaultLegislatorsLayout` providing the synchronous fallback.

## Legislator directory layout props contract

A unified properties contract supplies filtered representative rosters and interaction callbacks to all layouts.

The `ILegislatorsLayoutProps` interface defines the shared interface between container state and presentation layouts. It encapsulates the full and locale-filtered representative arrays, current tab selection, locale selector options, search-again callbacks, and lazy history retrieval state. Every theme layout implements this contract identically, ensuring consistent behavior across themes.

## DefaultLegislatorsLayout.tsx

The default directory layout presents representatives with neobrutalist borders and responsive card grids.

Extracted from the original page presentation, the default layout applies tokenized `border-neo` styling and neutral surfaces. It organizes locale switching and voting navigation along the top, stacking the locale selector row above a full-width voting link below the `sm` breakpoint so neither control overflows narrow mobile viewports, followed by tabbed score views and legislative history sessions. Cards render with progressive mounting past the initial fold threshold of eight entries.

## MonochromeLegislatorsLayout.tsx

Monochrome directory layout structures representatives as a compact single-column editorial register.

Designed for distraction-free reading, the monochrome layout constrains content to a 760-pixel single-column measure. A two-pixel header rule separates directory metadata from entries, while individual representative cards sit between one-pixel hairline border rules. Numeric values, term dates, and district numbers render in monospace tabular figures, matching the publication aesthetic.

## ServiceManualLegislatorsLayout.tsx

Service Manual directory layout presents representatives following authoritative public sector service guidelines.

The layout adopts the GOV.UK civic directory aesthetic, featuring a prominent top border rule paired with a four-pixel primary accent rule. A phase banner identifies the official municipal directory, and a structured filter well organizes jurisdiction selection. Representative cards feature a four-pixel primary left border that emphasizes structural hierarchy.

## SwissGridLegislatorsLayout.tsx

Swiss Grid directory layout presents representatives across an asymmetric ledger framed by exposed hairline rules.

The layout organizes content along an exposed one-pixel hairline grid. An asymmetric two-column structure places index numbers and labels within a 180-pixel left index column, aligning roster entries and tabbed views in the right content column. Zero border radii and zero box shadows enforce geometric precision across all viewports.
