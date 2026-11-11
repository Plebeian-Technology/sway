---
lat:
  mode: reference
---

# BillDetailScreen and BillOfTheMonthScreen

Both screens render the same three tabs through [[mobile-bill-surface-components-design#BillScreenTabs]]; they differ in where the bill's data comes from and in what sits above the tabs.

- `BillDetailScreen` (`mobile/src/screens/BillDetailScreen.tsx`) is the pushed screen for one bill, found by route id.
- `BillOfTheMonthScreen` (`mobile/src/screens/BillOfTheMonthScreen.tsx`) is the featured-bill screen.
- `BillOfTheMonthScreen` passes `hero` (the 30pt headline) and the test ids `botm-hero` and `botm-summaries`. `BillDetailScreen` keeps the normal headline size and uses `bill-detail-hero` and `bill-detail-summaries`.
- `BillOfTheMonthScreen` keeps `OfflineBanner` and `BrandHeader` above its scroll view and a `SwayLocalePickerSheet` (the locale switcher row) at the top of it, above the tabs.
- `BillDetailScreen` puts the tabs at the top of its scroll view; the pushed screen has no `BrandHeader`.
- The sponsor link navigates through the drawer, the parent navigator, to `Legislators` then `LegislatorDetail` with the bill's `legislator_id`; both screens pass it only when that id is present.
- The hearing card's "compare with representatives" button navigates through the same parent: `BillDetailScreen` goes to `Legislators` then `LegislatorsList` with `pop: true`, `BillOfTheMonthScreen` to `Legislators`. Both screens send "vote on past legislation" to `Bills`.

## Sections

The sections the two screens draw, in the order they appear within their tab.

- `BillHeader` — bill number and chamber, headline, category chips, sponsor (a link when the bill has a legislator id), status badge
- `VotePanel` — the For / Against buttons and a caption line
- `BillVoteStatus` — whether and when legislators voted, under the vote buttons
- `BillSummarySection` — the Sway AI summary, short first with a way to expand, then the official-source notice
- `BillAsIntroduced` — the full stored title under "As introduced"; renders nothing unless the title holds more than its headline (a deck after a dash or the legal enacting clause)
- `BillScoreBar` — how the whole locale voted ("How others voted")
- `DistrictVotesPanel` — how each district voted, with the reader's own district first, a matches/differs sentence for a reader who has voted, and each district's representatives under its bars
- `HearingTestimonySection` — "Take the next step" buttons and an in-app browser
- `RelatedNewsArticles` — approved news coverage; renders nothing when the bill has none
- `OrgPositionsSection` — "Why support" and "Why oppose" cards from organizations, hiding positions that have no summary
- `PublicTestimonySection` — constituent-letter counts by stance and a sheet to read them, for signed-in readers only

## Tabs

The sections are split into [[mobile-bill-surface-components-design#BillSectionTabs]], one tab mounted at a time.

- Bill: one hero card holding `BillHeader`, `VotePanel` and `BillVoteStatus`, then `BillSummarySection` with the "Report inaccurate summary" control under it (absent on archived bills, see [[bill-summary-reporting#Reader reporting of inaccurate summaries#Reporting from the mobile Bill tab]]), then `BillAsIntroduced`
- Votes: `VotePanel` in its own card, then `BillScoreBar` in a card, `DistrictVotesPanel` in a card (only when some district has votes), then `HearingTestimonySection`
- Summaries: `RelatedNewsArticles` when the bill has related articles, then `OrgPositionsSection`, then `PublicTestimonySection` when the reader is signed in and the bill has letters
- The Summaries tab holds no Sway summary. `OrgPositionsSection` always draws both cards, with a muted line when a card has no positions, so the tab is never blank.
- Both screens key the tabs by bill id: a different bill (a locale change on `BillOfTheMonthScreen`, a new route on `BillDetailScreen`) opens on the Bill tab; a refetch of the same bill keeps the selected tab.

## Loading and error states

The Votes and Summaries tabs follow the detail response; the Bill tab draws from the bill's own fields.

- The composer's `detailLoaded` flag is true once the detail response has arrived; `BillDetailScreen` passes it as always true, since the screen mounts the tabs only with data.
- Before it is true, Votes (the tally card) and Summaries (the organization positions) show a skeleton card. After a failure with no data they show the shared "could not load" sentence with a retry button that reloads the detail.
- The skeleton keys off `detailLoaded`, not off the score being null: the server sends `bill_score: null` for a bill with no score, and the hook sets its loading flag on every poll.
- The by-district card and the constituent-letter card draw nothing before the detail response arrives.
- `BillDetailScreen` shows a skeleton card while the first fetch is in flight and, if that fetch fails with no data, an empty state with a retry button inside a pull-to-refresh scroll view ([[bill-detail-error-recovery#Reaching a retry when the bill will not load]]).
- `BillDetailScreen` with a route id that is not a positive integer shows the same empty state with no retry control, and does not request the bill.

## Staying current

Both screens poll, subscribe to score updates and refetch after a vote; the pull-to-refresh spinner differs by screen.

- The reasons for `useFocusedSync`, the 15-second poll and the after-vote refetch delay are in [[bill-page-polling-props-rationale#Mobile: useFocusedSync on BillDetailScreen and BillOfTheMonthScreen]].
- [[mobile-sync-hooks#useFocusedSync]] polls every 15 seconds, subscribes to the `ScoreChannel` WebSocket channel and reloads on its `refresh_scores` message, and reloads when the network comes back, all only while the screen has focus.
- `BillDetailScreen` calls `useFocusedSync` once, to reload the bill. `BillOfTheMonthScreen` calls it twice: the screen shell reloads bootstrap, and the keyed body reloads the bill detail.
- After a vote, `BillDetailScreen` reloads the bill. `BillOfTheMonthScreen` reloads bootstrap and the bill detail.
- Loading: a skeleton card while the first fetch is still in flight. Refresh: pull down to refresh.
- `BillOfTheMonthScreen` reloads bootstrap and the bill detail on a pull, and shows the refresh spinner until neither bootstrap nor the bill detail is loading; the poll, after-vote and locale refetches show none.
- `BillDetailScreen` shows the refresh spinner only for a pull on the bill, until bill loading ends; the poll and after-vote refetches show none.
- A pull on `BillDetailScreen`'s error state has no bill data, so the screen switches to the loading skeleton and the spinner is never seen.

## BillOfTheMonthScreen's data source quirks

`BillOfTheMonthScreen` takes the featured bill from bootstrap and the rest from the bill detail response `BillDetailScreen` also uses, in two components that each own one source.

- Bootstrap's `bill_of_the_month` is `Bill#to_sway_json` (the `Bill#to_builder` hash) plus the reader's `user_vote`, merged in by `app/controllers/api/v1/bootstrap_controller.rb`. It carries the bill's own fields — title, summary, chamber, status, active, categories, link, vote dates, `legislator_id` — and no `sponsor`, `bill_score`, `organizations`, `districts`, `public_testimony_counts`, `related_articles` or `news_testimonies`.
- `BillOfTheMonthScreen`, the outer component, owns bootstrap, the loading skeleton, the empty state, `OfflineBanner`, `BrandHeader` and the first `useFocusedSync`, which reloads bootstrap.
- `BillOfTheMonthBody`, keyed by the featured bill's id, owns `useBill(botm.id)` (the `GET /bills/:id` response, see [[mobile-bill-hooks#useBill]]), the `ScrollView` with its pull-to-refresh, the second `useFocusedSync` (15 seconds) and the after-vote refresh.
- First paint comes from bootstrap alone: header, summary and vote buttons. The detail's bill fields are merged over it as `{ ...botm, ...detail.bill }`, which brings in `related_articles` and `news_testimonies`. The sponsor, `bill_score`, `organizations`, the reader's `districts` and `public_testimony_counts` are read from the detail response's top-level keys, and appear when the detail arrives. `user_vote` comes from bootstrap until the detail has loaded, then from the detail.
- `public_testimony_counts` is never read from bootstrap; it is null until the detail arrives and for a signed-out reader.
- A pull to refresh and the 1500 ms after-vote refresh each reload bootstrap and the bill detail. The rationale for the split is in [[mobile-bill-surface-components-design#BillScreenTabs#Why the featured screen fetches the bill detail too]].
- `isOnline` comes from `useCastUserVote()`. `useBootstrap` exposes neither `isOnline` nor a `refresh`; its refetch entry point is named `refetch`.
- `bootstrap` is cast through `unknown` to reach fields the server does send (`sway_locales`, `locale`) but that the `Bootstrap` interface does not list yet. `Bootstrap.locale` is typed as `Record<string, unknown>`; it is narrowed to the `{ id: number, name: string }` shape `SwayLocalePickerSheet` expects, and the cast is safe at runtime.
- Every refetch callback is wrapped in `useCallback`: the shell's depends on `refetch`, the body's on `bill.refresh`, which is stable, rather than on the whole hook result. Re-renders therefore do not resubscribe the focus effect or pile up extra polling timers inside `useFocusEffect`.
- The timer for the after-vote refetch is kept in a ref so a `useEffect` can cancel it when the screen goes away: React never looks at what `handleVoted` returns, so the cleanup has to live in a `useEffect`.
- Picking a locale really does switch locale — see [[docs/explanation/sway-locale-id-param-cookie-guard.md|sway-locale-id-param-cookie-guard.md]] for what `refetch(id)` does.

## BillDetailScreen's data source quirks

`BillDetailScreen` reads everything from one `useBill(id)` response, whose `bill` key holds the bill's fields.

- The bill record is `bill.data.bill`, falling back to `bill.data` itself; the sponsor, `user_vote`, `bill_score`, the reader's `districts`, `organizations` and `public_testimony_counts` are top-level keys of the same response.
- The locale slug and generic portal URLs passed to `HearingTestimonySection` and `BillSummarySection` are resolved from the bill's own `sway_locale_id` against `bootstrap.sway_locales` (falling back to `bootstrap.locale`), so the source links point at the bill's government website even when the user's active locale is elsewhere.
- The signed-in flag for the constituent-letter card comes from `useSession().isAuthenticated` on both screens.
