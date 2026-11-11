---
lat:
  mode: explanation
---

# Lazy Inertia props

A prop a partial reload might not name is supplied as a callable rather than an already-computed value, so Inertia's resolver can skip the ones it did not ask for.

The Bill Creator new action and Legislators index use callables for props their partial reloads do not request. The edit action keeps a separate shape and still builds pipeline-control state before render.

## Why the props became callables

The resolver decides whether a prop is excluded before it evaluates it, so a prop supplied as a value has already been paid for by the time it is discarded, while a prop supplied as a callable costs nothing.

The shared JSON resolver calls a prop's block with the request controller as its
receiver so controller helpers remain available. Steep cannot infer that
dynamic receiver for `instance_exec`, so the narrow ignore marks that mismatch
at the call site rather than hiding a runtime failure.

The Bill Creator polls twice a minute per open tab, and neither poll's list names
most of the props the action builds. A full locale roster of legislators, a scan
of every category, a bill's campaigns and the sending-service domain panel were
each computed and thrown away on every tick.

The JSON resolver also evaluates callable props so legacy bearer and JSON
clients receive the existing response. The eager bill prop `public_testimony_counts`
supplies letter counts by stance as a callable, while the bill props
`legislator_votes`, `districts`, and `public_testimony_letters` are optional on
initial Inertia responses; JSON clients retain them unless they explicitly
request omission.

## Mobile JSON omission is an explicit request

The mobile contract preserves the existing JSON body unless a client names an allowed optional prop in `X-Sway-Omit-Props`.

The header is a scalar CSV capability request, not an app-version signal or
navigation parameter. Its parser trims each item, matches exact case-sensitive
prop names, ignores blanks and unknown names, and treats duplicate names as one
request. Non-string values are ignored. Only these top-level `OptionalProp`
values may be omitted: `legislators`, `legislator_votes`, `districts`, and
`public_testimony_letters`. All four are optional props defined on
[[app/serializers/bill_page_resource.rb#BillPageResource]].
[[app/controllers/concerns/mobile_format_negotiation.rb#MobileFormatNegotiation#requested_optional_prop_names]] parses the header, and [[app/controllers/concerns/mobile_format_negotiation.rb#MobileFormatNegotiation#resolve_inertia_props]] filters only matching top-level optional values before recursive resolution. Without the header, legacy JSON resolves every prop as before, so no version gate is needed. The one header-independent difference in a JSON bill body is an extra `legislator_names` key on each `bill_score.districts` entry, described in [[district-chart-tooltip#The mobile bill JSON carries the names, the web page does not]]. JSON `Vary` includes this header while preserving existing tokens, including when the header is absent; browser responses keep their current Inertia behavior.

This boundary is deliberately narrower than the resolver's callable support.
The deferred `bills` list stays available to list clients, and `history` stays
available to its active mobile reader. Plain `Proc` values, nested values,
unlisted props, and serialized resource fields are not omission targets. The
established `organizations` and `organization_bill_positions` bill keys remain
separate wire keys in [[app/models/bill.rb#Bill#render]].

Two mobile screens call [[mobile/src/hooks/useBill.ts#useBill]]: the bill detail
screen and the Bill of the Month screen's keyed body. Their initial, poll and
refresh requests all send the omission header, naming `legislators`,
`legislator_votes` and `public_testimony_letters` and leaving `districts` out.
[[mobile/src/hooks/usePublicTestimony.ts#usePublicTestimonyLetters]] sends no
header and does not request the bill at all: it reads the letters from their own
endpoint, described in
[[testimony-letters#Reading the letters inside a testimony bundle#Browsing constituent testimony in the modal]].
The omittable `public_testimony_letters` prop and the header handling stay for
installed app versions that still read the letters from the bill body. Bill
of the Month paints first from the bootstrap payload, which serializes the
featured bill through
[[app/controllers/api/v1/bootstrap_controller.rb#BootstrapController#show]]
and is outside this response resolver.

## Current optional and deferred JSON props

Six declarations currently reach the shared JSON resolver: the deferred bill list, four optional bill detail props, and optional legislator history.

| Prop | Current declaration and JSON path | Mobile use |
| --- | --- | --- |
| `bills` | [[app/controllers/bills_controller.rb#BillsController#index]] declares the list with `InertiaRails.defer` and sends it through [[app/controllers/concerns/mobile_format_negotiation.rb#MobileFormatNegotiation#render_inertia_or_json]]. | [[mobile/src/hooks/useBills.ts#useBills]] reads `res.bills` for the paged list; this value stays resolved. |
| `legislators` | [[app/serializers/bill_page_resource.rb#BillPageResource]] declares the roster optional; [[app/controllers/bills_controller.rb#BillsController#show]] and [[app/controllers/bill_of_the_month_controller.rb#BillOfTheMonthController#index]] send shared bill props through JSON resolution. | No mobile hook reads it and each requests omission. [[mobile/src/screens/BillDetailScreen.tsx#BillDetailScreen]] and the Bill of the Month screen's body call the detail hook. |
| `legislator_votes` | [[app/serializers/bill_page_resource.rb#BillPageResource]] declares votes optional on the initial Inertia response; JSON still resolves them unless requested for omission. | No mobile hook reads this prop and each requests omission. |
| `districts` | [[app/serializers/bill_page_resource.rb#BillPageResource]] declares the reader's districts optional on the initial Inertia response; JSON still resolves them unless requested for omission. | The detail hook reads it, matching the reader's districts against the per-district tallies in [[mobile/src/components/DistrictVotesPanel.tsx#DistrictVotesPanel]], and does not request omission. The letters hook does not read it. |
| `public_testimony_letters` | [[app/serializers/bill_page_resource.rb#BillPageResource]] declares browsable public constituent letters optional on the initial Inertia response; JSON still resolves them unless requested for omission. | The detail hook requests omission, so the 15-second poll never downloads letters. [[mobile/src/hooks/usePublicTestimony.ts#usePublicTestimonyLetters]] reads them from the letters endpoint instead of the bill body, and [[mobile/src/components/BrowseTestimonySheet.tsx#BrowseTestimonySheet]] shows them. |
| `history` | [[app/controllers/legislators_controller.rb#LegislatorsController#history_prop]] makes only the default history value optional; an explicit history request supplies eager data. | [[mobile/src/hooks/useLegislators.ts#useLegislators]] reads the value for the history tab, so this contract leaves it untouched. |

The notifications subscription is deferred only for the Inertia controller, and the five Bill Creator optional props (`summary_prompt`, `summary_source_documents`, `summary_revisions`, `testimony_campaign_letters`, and `public_testimony_letters`) are excluded from mobile builder output before JSON resolution. Neither group is part of the mobile JSON inventory. The two bill keys remain `organizations` and `organization_bill_positions` as defined by [[app/serializers/bill_page_resource.rb#BillPageResource]]. The page composition is described in [[system-shape#System shape#One process, two languages#The bill page composes a page payload from several contracts]].

## Payload size matters on slow connections

Payload size binds delivery for Sway readers: progressive rendering matters more as the connection degrades, even when localhost timing is fast.

The roster tooltip change in [[district-chart-tooltip#The roster is fetched when a reader asks for it]] keeps the district label immediate and fetches the representative's name only when a reader asks. One request supplies every bar's name, and the component remembers that request; commit `9f00e0f7f` records why this progressive behavior matters. The 535-member US roster is the historical example, not a current runtime measurement. On a degraded connection, keeping the chart readable immediately and deferring the representative name matters more; localhost timing alone does not justify restoring eager delivery.

## Preload savings depend on result size

An attachment preload saves repeated reads for a list but adds a read for a single record.

The measured example is ten organization rows without preload causing twenty extra attachment reads, while a single organization with preload took three reads instead of two. [[public-organizations-endpoint#Why the list preloads icons and the detail does not]] applies that row-scaled rule to the endpoint without restating the measurement.

## The Legislators index applies the same rule

The Legislators page polls every fifteen seconds for the roster alone, so the two props that poll never names — the end-of-term banner flag and the search filter — are callables for the same reason.

The banner flag costs a membership query whenever the roster comes back empty,
which is the state the page sits in while a term is between rosters, so the poll
paid for that query on every tick. The filter costs no query and is a callable
only so the pair read alike.

## Why shared work sits behind memoized methods

Several props derive from one source, and moving that derivation inside each lambda would compute it once per prop rather than once per request, turning a saving on a poll into a loss on a full page load.

The cleaned-testimony artifact is the clearest case, since four props read from a
single parse of it. It is derived by one memoized method, as are a bill's
campaigns and the sending-service domain panel, so a request wanting all four
still parses once.

## Sorting a loaded association in Ruby

Two of the Bill Creator's props read the same bill's categories, and the second sorts the array the first already loaded rather than asking the database for the same rows in order.

`order` on an association builds a fresh relation, so it goes back to the
database for rows sitting in memory, and the association cache Rails just filled
goes unread. A bill carries a handful of categories, so Ruby's own sort costs
less than the round trip, and the two orderings agree on the ASCII names
categories are given.

## What laziness cannot undo

A prop that is never evaluated still cannot prevent work that happened before the prop hash existed.

The action's `before_action` loads the bill with its legislator votes eagerly, so
that query runs on every request whatever the poll asked for. Making the
`legislator_votes` prop lazy takes it out of an Inertia response and skips
turning each vote into JSON, while leaving the query exactly where it was. The
mobile omission also saves serialization only; it does not move that eager
query.

The distinction matters when reading the specs here. They assert that an excluded
prop is absent from the response, rather than that no query ran — except for the
four props above, where no query genuinely runs and the specs say so.
