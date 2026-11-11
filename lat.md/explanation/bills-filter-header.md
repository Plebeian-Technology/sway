---
lat:
  mode: explanation
---

# Bills filter header

The four filter controls on `/bills` — locale, sort, search, categories — sit in one wrapping flex row per layout, and the order a reader meets them in is not the order they appear in the markup.

The controls themselves are covered by [[bills-category-filter]]; this is about where they land on the page.

## Why the categories control gets its own line

Categories is the only control whose trigger carries a variable-length sentence — the picked names in order, which run past the width of a field as soon as a reader picks a second one.

Sharing a line with locale, sort and search squeezed it to a width where the trigger truncated at one or two names, so the control could not report the state it exists to report. A full row lets the trigger grow instead.

The break is declared rather than left to wrapping. Every themed layout lays its controls out with `flex-wrap`, so a fourth field falls to the second line only while the first three happen to fill the first one; a wider viewport, a shorter locale name or a fifth field pulls it back up. `--wide` modifiers (`csl-field--wide`, `ball-field--wide`, `bnl-field--wide`) set `flex-basis: 100%`, and the default layout uses `md:w-full` for the same reason.

## Why the fields are ordered twice

`DefaultBillListLayout` writes its fields in mobile order and reorders them for wider viewports with `md:order-*` rather than rendering two sets.

The two orders genuinely differ. Mobile leads with locale and search, because those are the two a reader arrives wanting; wide viewports put sort between them, which is where the eye expects a sort control next to what it sorts. Rendering both orders would mean two copies of every field, so two elements would share each `id` and a label would point at whichever the browser found first.

## Why sort and categories collapse only on mobile

On a phone the four stacked fields pushed the first bill below the fold, so sort and categories — the two a reader reaches for second — hide behind a `More options` disclosure and locale and search stay in view.

The disclosure is a plain button with `aria-expanded` and `aria-controls`, and the panel is hidden with a class rather than unmounted. That is what lets the same markup serve both viewports: at `md` and up the panel carries `md:contents`, so its two children rejoin the outer flex row and take their `md:order-*` places, and the trigger itself is `md:hidden`. A Radix `Accordion` — which `CollapsiblePanel` wraps — could not do this, because it removes closed content from the tree, so sort and categories would vanish on desktop too unless they were rendered a second time.

Keeping the fields mounted also keeps them reachable to the layout sweeps in `list-layouts/__tests__/`, which render each layout in jsdom where no viewport applies and query the sort select directly.

## Why the page is scoped to the current legislative session

The `/bills` page defaults to bills from the current legislative session for the selected locale, while exposing a session selector for historical sessions.

The public list serves voters tracking active legislation first, so the default query filters against `Bill.current_session` before any search or category filters are applied. Readers who want to inspect an earlier session can pick it from the session selector (`bills_legislative_session_id`), whereas `/past_bills_of_the_month` filters strictly to previous Bills of the Month across sessions and omits the session selector.

## Why bills are sorted by introduction date by default

When first loading the `/bills` page, bills are returned in descending order of their `introduced_date_time_utc`, followed by a tie-breaker on `external_id` descending.

This default ordering surfaces the newest legislation to readers immediately. The sorting applies to the server-rendered `bills_index_scope` query and is the baseline order before a user explicitly interacts with the client-side sort control.
