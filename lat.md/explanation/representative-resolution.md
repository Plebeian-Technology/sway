# Representative resolution by seat

Registration resolves supported current offices by persisted seat identity so concurrent seats survive and ambiguous occupancy cannot change reader links.

## Seat identity

Each supported term points to a persisted [[app/models/seat.rb#Seat]] within one [[app/models/district.rb#District]].

District remains the geographic boundary and owns its service terms; a Seat distinguishes each official office inside that district.

Source-backed office identity is scoped to that district. Legacy terms may retain a nil seat, but registration never links a selected current term without persisted identity; it skips that term and never derives a seat from a person's name, term year, or district number.

## Occupancy interval

Seat service uses the half-open interval returned by [[app/models/term_window.rb#TermWindow]].

Same-day handovers are valid, overlapping intervals for one seat are refused, and a vacancy produces no occupant. Resolution checks every current row for each selected seat, including rows omitted by a geographic endpoint and duplicate rows for one person.

## Locale-wide district

The locale document identifies its locale-wide district by the exact stored name in `representative_resolution.locale_wide_district_name`.

Congress declares `US0`; Maryland and Baltimore declare `MD0`. This avoids treating the first numeric-zero district in Congress as nationwide when state Senate seats also use names such as `MD0`.

## Congress fallback

Every address is resolved against the US Congress locale, whatever country it names, so a user outside every supported place still gets the federal officials the address reaches.

[[app/models/address.rb#Address#sway_locale_attribute_sets_for]] always gives the Congress set the country `US`. The city set needs a city and a region, and the state set needs a region, because neither names a place without them; a blank country counts as the United States, the column's default. A set built from blank parts used to fail while naming its locale, which answered the user with a server error.

Within Congress the address's state comes from [[app/models/address.rb#Address#us_state_code]]: a region that is a US state code other than `US` itself, with a country that is blank or the United States. The Senators sit in the state's district 0 ([[representative-resolution#Congress seat identity conventions]]), so a known state always yields its two Senators. The House member is added only when Census places the coordinates in a district. [[app/services/sway_registration_service.rb#SwayRegistrationService#congress_district_numbers]] asks Census only for a located address, keeps district 0 alone when Census finds no district, and keeps district 0 alone when Census fails.

A Census failure is recorded in `skipped_resolution_errors` and reported to Sentry at warning level, the way a skipped term is ([[representative-resolution#Resolution branches]]). Registration therefore keeps the Senators, records the Congress locale for a later retry, and reconciliation keeps refusing to change links while Census is down.

When the state is unknown no geographic term is kept, so only the occupants of the locale-wide district remain ([[representative-resolution#Locale-wide district]]), which for Congress is the President. The seeded roster has no current President term, so such an address can still resolve nobody; registration then completes the user with the Congress locale waiting ([[registration-dead-ends#An empty list says which kind of empty it is]]).

## Resolution branches

[[app/services/sway_registration_service.rb#SwayRegistrationService#district_legislators]] applies one seat validation to geographic and OpenStates regional candidates, then adds the locale-wide district's current occupants.

Candidate terms, seats, districts, and legislators must agree on the selected locale. A term that fails one of these checks is skipped rather than raised: a term with no seat, a seat outside its locale or district, and every occupant of a seat with more than one current occupant. One bad roster row would otherwise refuse every registration it reaches, and a locale-wide office reaches every address in its locale. The user gets the missing representative later.

[[app/services/sway_registration_service.rb#SwayRegistrationService#skip_unresolved_terms]] records each skip once in the `skipped_resolution_errors` reader, as the `Seats::UnresolvedSeatError` or `Seats::OverlapValidator::OverlapError` the check would have raised, logs it with term ids, district and locale names, and reports it to Sentry at warning level. An overlapping seat yields one error for all of its occupants.

A skipped term never deactivates a stored link. Reconciliation still refuses: [[app/services/reconcile_user_districts_service.rb#ReconcileUserDistrictsService#call]] resolves the complete set before [[app/services/reconcile_user_districts_service.rb#ReconcileUserDistrictsService#apply_diff]] and raises the first recorded skip. An address switch skips like registration does, because raising there would answer the user with a server error. [[app/services/user_address_switch_service.rb#UserAddressSwitchService#call]] leaves out of its stale set every legislator in the `skipped_legislator_ids` reader, and that legislator's district, so their links stay active.

## Unconfigured offices

Registration skips a current term that has no seat and whose title names an office absent from the locale's `seat_chambers`, silently. Every other unseated current term is skipped and reported, as [[representative-resolution#Resolution branches]] describes.

[[app/services/sway_registration_service.rb#SwayRegistrationService#unseated_unconfigured_office?]] looks the title up through [[app/models/sway_locale/term_rules.rb#TermRules#seat_chamber_for]], which applies the same `State Delegate`/`State Senator` aliases the seeder uses. The seeder already declines to seat these offices, so a holdover term for one of them can never gain a seat. Refusing it would block registration for every address in the locale, because the locale-wide district reaches every address.

The silent skip is narrow on purpose. A seated term always passes through, whatever its title, because it already carries its identity. A term with no title, a locale that configures no seat chambers, and a configured office without a seat are recorded and reported, because those cases are missing identity for an office registration is meant to link. Reporting the unconfigured holdover offices would send a report for every registration in their locale.

## Configured seat identity for person-keyed rosters

Configured chamber mappings allow person-keyed rosters to establish distinct seats during seed ingestion without requiring live external network requests.

While seat-keyed rosters like Baltimore receive published seat labels directly from their source feed, person-keyed rosters in Congress and Maryland identify representatives by person identifiers (`bioguide` and `openstates`).

The selected architecture allows `term_rules.seat_chambers` on `identified_by: person` locales in [[app/models/sway_locale/document_reader.rb|SwayLocale::DocumentReader#validate_seat_chambers]]. This enables [[db/seeds/models/seed_legislator_terms.rb#SeedLegislatorTerms]] to resolve and attach distinct [[app/models/seat.rb#Seat]] records using published role metadata during seed preparation. This approach avoids requiring live or fixture-backed official service evidence profiles for all 546 Congress terms and 191 Maryland entries during offline seeding and container boot. Relaxing the validator preserves offline execution, idempotency, and sub-second performance while keeping registration logic purely consumer-side.

## Congress seat identity conventions

Congress distinguishes House single-member district seats and Senate class seats using source-published term metadata.

House representatives occupy single-member district seats scoped to their state and district number. In [[db/seeds/seed_preparers/legislators/congress_dot_gov.rb|SeedPreparers::Legislators::CongressDotGov]], the seat identifier follows the format `<state_downcase>-house-district-<district_number>` (for example, `md-house-district-3` for Maryland's 3rd congressional district, or `wy-house-district-0` for at-large districts). Each House seat associates with chamber `House of Representatives` and title `Rep.`.

Senators represent their entire state and attach to the state's `XX0` district (such as `MD0` or `WI0`). Because each state seats two co-serving Senators with staggered six-year terms, their seats are distinguished by constitutional class using the format `<state_downcase>-senate-class-<1|2|3>` (for example, `md-senate-class-1` and `md-senate-class-3`). The Senate class is read strictly from the published `term["class"]` field populated from `unitedstates/congress-legislators` by [[app/services/legislators_cache/congress_term_history.rb|LegislatorsCache::CongressTermHistory]] into `legislators.json`. It is never guessed or inferred from `endYear` or election cycles, because mid-term appointments, special elections, and term window widening produce end years that deviate from regular six-year cycles.

The nationwide `US0` executive district holds no legislative seat. Unevidenced presidential sentinel terms are retired during seeding when official service evidence is unsupported, and `seat_chambers` for Congress covers only `Sen.` and `Rep.`.

## Maryland seat identity conventions

Maryland establishes distinct seat records across statewide executive offices, single-member Senate districts, and multi-member House delegations.

The Maryland locale document declares `identified_by: person` and maps three titles in `term_rules.seat_chambers`: `Senator: Senate`, `Delegate: House of Delegates`, and `Governor: Executive`. `Lt_Governor` and `Attorney General` are deliberately left out, because those offices have no legislative function.

External payloads and legacy test fixtures may report titles as `State Delegate` or `State Senator`. [[db/seeds/seed_preparers/legislators/open_states.rb|SeedPreparers::Legislators::OpenStates]] and [[db/seeds/models/seed_legislator_terms.rb|SeedLegislatorTerms]] normalize these variants using `TITLE_ALIASES` (`State Delegate => Delegate`, `State Senator => Senator`). This canonical title determines office identity derivation, cohort grouping, chamber lookup, and persisted seat title, preventing duplicate seat creation while preserving prepared term titles.

Statewide executive offices in `MD0` represent single-holder constitutional positions. [[db/seeds/seed_preparers/legislators/open_states.rb|SeedPreparers::Legislators::OpenStates]] formats these offices as `<region_downcase>-<normalized_title>-0`, yielding `md-governor-0` under chamber `Executive` (and `md-lt-governor-0` or `md-attorney-general-0` whenever those titles are mapped again).

The Maryland Senate consists of 47 single-member districts (`MD1` through `MD47`). Each Senator occupies a district-scoped seat formatted as `<region_downcase>-senator-<district_number>` (for example, `md-senator-46` in district `MD46`) under chamber `Senate` and title `Senator`.

The Maryland House of Delegates seats 141 members across the 47 districts under chamber `House of Delegates` and title `Delegate`. In single-member subdistricts (such as `44A` or `33A`), the seat identifier is `<region_downcase>-delegate-<subdistrict_downcase>` (such as `md-delegate-44a`), which remains durable across successor elections. In multi-member delegations—including 2-member subdistricts like `44B` and 3-member at-large districts like `MD18` and `MD46`—delegates share the same geographic district without separate state-assigned seat numbers. To prevent concurrent occupancy collisions during registration, seats are assigned deterministic slot keys `<region_downcase>-delegate-<district_or_subdistrict_downcase>-<slot>` (for example, `md-delegate-18-1`, `md-delegate-18-2`, and `md-delegate-18-3`, or `md-delegate-44b-1` and `md-delegate-44b-2`), ordered ascending by published OpenStates person identifier (`ocd-person/...`).

### Executive offices without a configured chamber

A roster entry classified as an executive office whose title has no `seat_chambers` mapping is skipped by the seeder rather than raised as an unresolved seat.

[[db/seeds/models/legislator.rb#SeedLegislator#unconfigured_executive_office?]] applies the rule using [[db/seeds/seed_preparers/legislators/open_states.rb#OpenStates#executive_office?]], which reads `current_role.org_classification`. The roster JSON still carries Maryland's Lieutenant Governor and Attorney General, so restoring the mapping in the locale document brings them back without a roster refetch. Legislative titles keep the strict check: an unmapped `Senator` or `Delegate` still raises `Seats::UnresolvedSeatError`, so a roster typo cannot silently drop a member. A previously seeded holder of a now-unmapped office is absent from the fresh roster, but departure reconciliation does not end the term without official departure evidence, so the term stays current and unseated. [[representative-resolution#Representative resolution by seat#Unconfigured offices]] keeps such a holdover out of registration.

## Seat validation, attachment, and handover semantics

Seed ingestion attaches validated seats to current terms while preserving temporal interval integrity and concurrency guarantees.

[[app/models/sway_locale/document_reader.rb|SwayLocale::DocumentReader#validate_seat_chambers]] verifies that configured chamber mappings specify non-blank string titles and chambers for both seat-keyed and person-keyed locales. During seeding, [[db/seeds/models/seed_legislator_terms.rb#SeedLegislatorTerms]] resolves the prepared seat context, verifying that the prepared district belongs to the locale, that the member is actively serving, and that the member's title is declared in `seat_chambers`.

[[app/models/seat.rb#Seat|Seat.find_or_create_by_identity!]] finds or creates the district-scoped seat record with matching title and chamber metadata. Before attaching the seat to a current term, [[db/seeds/models/seed_legislator_terms.rb#SeedLegislatorTerms]] evaluates existing terms on that seat using the half-open interval `[begins_on, ends_on)` defined by [[app/models/term_window.rb#TermWindow]].

Same-day handovers between departing incumbents and incoming successors succeed because `incumbent.ended_on <= successor.begins_on` produces zero overlap under the half-open interval convention. If another legislator holds an overlapping interval on the same seat, [[db/seeds/models/seed_legislator_terms.rb#SeedLegislatorTerms]] logs a warning and leaves `term.seat_id` unattached rather than corrupting seat occupancy. If the same legislator holds overlapping terms on the same seat, an overlap error is raised. [[app/services/sway_registration_service.rb#SwayRegistrationService]] subsequently skips and reports any current term lacking a valid, unconflicted seat, so ambiguous or overlapping representation never links to registered citizens.
