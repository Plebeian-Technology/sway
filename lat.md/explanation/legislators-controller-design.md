---
lat:
  mode: explanation
---

# LegislatorsController design

`LegislatorsController` coordinates representative directories, voter agreement calculations, and legislative term transitions.

The controller delivers representative rosters, session history, and agreement scoring for constituents across supported geographic jurisdictions.

## Detail page has its own response

The detail action renders one legislator's page and adds the score pair available to the current user's link. It remains public for readers who arrive from a public bill sponsor.

Both list and detail paths check `table_exists?` on [[app/models/historical_score_explanation.rb#HistoricalScoreExplanation]] before querying explanations so databases without the repair audit tables still serve representative pages cleanly.

## Active term is loaded before detail serialization

The detail action preloads a legislator's active term because the resource reads that term's title, district, and service state while building the page.

## List data is reused within one request

The list memoizes its serialized rows because the response also checks whether every linked representative's term has ended.

## Representative rows stay within the viewed locale

List rows are selected from the locale being viewed and require an active term. Historical representatives arrive through the separate history payload.

## Score props retain their established shape

List rows and detail responses carry `user_legislator_score` and `lifetime_score`; the detail path can also render for a deactivated history link. [[scores-and-agreement#Every score is bound to a term]] owns score meaning and aggregation, while [[current-legislator-term#Which term a payload describes]] owns the displayed term.

Executive offices follow the standard legislative score path: `user_legislator_score` and `lifetime_score` resolve through [[app/serializers/user_legislator_term_score_resource.rb#UserLegislatorTermScoreResource]] for active and historical terms identically to legislative chambers.

## Bill of the Month voting record lives on the detail payload

[[app/controllers/legislators_controller.rb#LegislatorsController#legislator_with_score]] merges `bill_of_the_month_votes` onto the detail response rather than adding an unconditional attribute to [[app/serializers/legislator_resource.rb#LegislatorResource]].

Attaching [[app/controllers/legislators_controller.rb#LegislatorsController#bill_of_the_month_votes_for]] to the detail hash refreshes the voting record automatically during partial reloads of the `legislator` prop on score updates while keeping the directory and `/api/legislator_votes` payloads and query counts untouched. Filtering [[app/models/bill.rb#Bill]] by `sway_locale_id` avoids loading the [[app/models/sway_locale.rb#SwayLocale]] record, and returning early when no released bills exist skips both [[app/models/legislator_vote.rb#LegislatorVote]] and [[app/models/user_vote.rb#UserVote]] queries. Because the unique index allows one [[app/models/legislator_vote.rb#LegislatorVote]] per bill and term, ordering by the [[app/models/legislator_term.rb#LegislatorTerm]] `term_start_year` and vote id before indexing ensures a representative's latest term governs when multiple term rows exist for the same bill.

### Term and chamber eligibility filter

[[app/services/legislator_bill_eligibility.rb#LegislatorBillEligibility|LegislatorBillEligibility.eligible?]] narrows released Bills of the Month to legislation where the representative holds a recorded vote or served in a voting chamber when the bill came up.

Without this filter, a former representative's page lists bills released after they left office, a newly seated member appears with "No vote recorded" on bills from prior sessions, and a representative in a bicameral body appears as unrecorded on bills that never reached their chamber. Any bill with a recorded [[app/models/legislator_vote.rb#LegislatorVote]] for that representative remains visible regardless of term dates. For unvoted bills, [[app/services/legislator_bill_eligibility.rb#LegislatorBillEligibility]] resolves each term's chamber from [[app/models/seat.rb#Seat]] metadata, the locale's declared `term_rules.seat_chambers` mapping under [[representative-resolution#Congress seat identity conventions]] and [[representative-resolution#Maryland seat identity conventions]], and the President's office in [[app/models/congress_chamber.rb#CongressChamber]]. Terms without a resolved chamber remain eligible for any legislative chamber so missing metadata never hides a bill, and executive terms match any bill in the jurisdiction whose relevant date falls within their term window. Term date intervals follow [[app/models/term_window.rb#TermWindow|TermWindow.begins_on]] and [[app/models/term_window.rb#TermWindow|TermWindow.ends_on]], and a term in a locale with no declared calendar and no stored dates is skipped for the reason given in [[legislator-term-current-and-covering#Why scope :current skips a locale with no declared calendar, rather than raising]].

Each chamber check evaluates that chamber's own vote date (`house_vote_date_time_utc`, `senate_vote_date_time_utc`, or [[app/models/bill.rb#Bill#vote_date_time_utc]] for council bills), falling back to `introduced_date_time_utc` and then `scheduled_release_date_utc` when chamber vote timestamps are blank. Prioritizing the chamber vote date over `introduced_date_time_utc` intentionally diverges from [[app/services/score_recompute_service.rb#ScoreRecomputeService|ScoreRecomputeService.tally_agreement]], which binds agreement tallies to terms by `introduced_date_time_utc` as described in [[scores-and-agreement#Every score is bound to a term]]: a bill introduced before a mid-term appointment or chamber crossover can still come to a floor vote after the member takes their seat, so the chamber vote date answers whether the representative could have voted on the bill.

## History is resolved only when requested

The history payload is optional for the first page response and limited to the viewed locale. Opening the History tab requests it without putting stale history in routine score polling.

## Forced history failure is test-only

The test-only forced-error parameter counts actual History reload attempts and returns an Inertia `errors` prop, so retry coverage can distinguish a fresh request from a redraw.

## Why waiting_for_new_term distinguishes empty list causes

`waiting_for_new_term?` distinguishes accounts awaiting initial district discovery from constituencies whose legislative terms expired before new rosters were seeded.

When all recorded terms for a user's legislators have completed, initiating another search cannot uncover active representatives. In this situation, [[app/frontend/sway_constants/parityCopy.ts#PARITY_COPY]] provides `legislators.waitingForNewTerm` to explain the inter-term transition and suppress redundant search actions.

## Why the frontend legislator route helper accepts two argument shapes

The `legislator` helper in `app/frontend/sway_constants/routes.ts` normalizes both legacy and standard argument shapes to `/legislators/:id`.

`config/routes.rb` defines `/legislators/:id` as the single member route. Earlier helpers attempted constructing two-segment paths (`/legislators/:localeName/:external_id`) that failed on cross-origin redirects. Accepting either single id arguments or legacy `(localeName, id)` pairs ensures backwards compatibility while reliably targeting the canonical route.

## Why legislator_with_score doesn't require active: true

`legislator_with_score` constructs detail representations for former legislators reached from deactivated history links without requiring active service terms.

Former representatives lack active terms, but their detail views remain accessible from historical records. `#current_term_score_for` resolves scores against frozen historical term rows while `LegislatorResource` derives title and district attributes from their most recent term.

## Why Legislator.tsx shows the "Representatives" back link only to signed-in users

The breadcrumb navigation link to `/legislators` renders exclusively for authenticated users because the index requires authentication.

Single legislator detail pages are publicly accessible from bill sponsor links, whereas the representative index is gated behind user sign-in. Hiding the back link for unauthenticated visitors prevents leading them into sign-in redirects.

## Why Legislator.tsx treats active === false as its own case

`Legislator.tsx` recognizes deactivated representatives without active terms directly from server flags.

Former representatives return `active === false` (`Legislator#serving?`). Deactivated user-legislator records supply frozen score tallies from the representative's final term, eliminating client-side fallback score calculations.

## Why Legislator.tsx district label checks typeof === "number"

District label formatting checks `typeof === "number"` to guard against missing district identifiers.

District numbers can arrive undefined in edge cases. Checking `typeof === "number"` handles null and undefined values cleanly without producing "District undefined" in client UI.

## What Legislator.test.tsx pins about the tab wording

`Legislator.test.tsx` pins precise tab label formatting and status badge display across serving and former legislators.

Active representatives display "Current term" with supporting session year ranges. Former representatives display term years as tab titles alongside an "Ended" status stamp.

## Why LegislatorsLocaleGuard.test.tsx is its own file

`LegislatorsLocaleGuard.test.tsx` isolates rendering assertions for scenarios where locale contexts are completely absent.

When locale contexts are absent, reading `locale.name` directly would trigger unhandled exceptions. Dedicated guard specifications test missing locale fallbacks independently from standard polling suites.

## Why current_term_score_for picks the row it does

`current_term_score_for` selects score rows matching active service terms for serving members and frozen final-term rows for deactivated links.

Serving representatives receive score tallies bounded to their current legislative term. Deactivated historical links select the most recent frozen term score. Scoring operations reuse preloaded arrays to minimize query counts.

## Browser coverage for the list-to-detail navigation

System specifications in `spec/system/legislators_navigation_spec.rb` verify end-to-end navigation from representative cards to detail views.

Browser tests ensure card links navigate cleanly to `/legislators/:id` without triggering cross-origin redirect exceptions.

## Testing the retry button with an XMLHttpRequest open counter

History retry specifications count `XMLHttpRequest.prototype.open` invocations to verify fresh network dispatches.

`spec/system/legislator_history_spec.rb` simulates forced reload failures and instruments `open()` calls, proving retry interactions dispatch new network requests rather than redrawing cached DOM elements.

## Browser coverage for the detail page

System specifications in `spec/system/legislator_detail_spec.rb` validate chart rendering and contact actions on legislator detail pages.

Tests confirm voter agreement panels render only when score records exist and verify test identifiers across contact channels. Fixture setup explicitly associates current legislative terms so score serialization completes.

