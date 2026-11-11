---
lat:
  mode: explanation
---

# Jurisdiction declarations

Jurisdiction rules name each locale's sources and chambers explicitly. A fallback based on locale kind could silently read another city's Legistar records or use the wrong state roster.

Declarations live in code because these values determine which civic records
Sway believes. The jurisdiction and term registries must cover the same locales;
their specs enforce that pairing. Display rules can degrade when undeclared,
but writes refuse to manufacture scores from unknown source rules.

The planned [[locale-extension#Planned declarative contract]] moves those
declarations into validated locale data while retaining strict readers and
allowlisted implementations. The data format alone cannot make a provider
support another jurisdiction.

## Source pairing

Each source requires its own jurisdiction identifier. A source name alone cannot distinguish two cities on Legistar or two states on OpenStates.

Legistar voting requires a nonblank legistar_client, and only Legistar voting
may declare one. Similarly, Legistar legislation and hearings rules require an
explicit `client` identifier; adapters raise `ArgumentError` when omitted rather
than falling back to locale city names. OpenStates roster or vote sourcing similarly
requires open_states_jurisdiction. Bang readers refuse an absent identifier rather than
letting a client borrow its default. The roster refresher is separately declared
and checked against an allowlist, so a typo fails at construction.

Congress uses its declared Congress sources and congress_ordinal session
numbering; Maryland and Baltimore use term_years. A new locale has no implied
Baltimore source configuration.

## A test fixture names a jurisdiction in full or not at all

A locale built for a test either names city, state and country together or names none of them, because naming part of one rotates the rest through a place that does not exist.

The factory rotates over the jurisdictions Sway really seeds rather than
inventing city names, so two bare locales in one example can land on the same
one. A spec that already named a jurisdiction and then creates a second locale
therefore names that one explicitly too — the built-in traits exist for exactly
that — since a bare create can collide with the one already named, and a
uniqueness constraint scoped to a locale then fails for a reason the example is
not about.

An organization's name is unique within its locale, which is the same trap seen
from the other end: a factory handing out one fixed organization name worked
only while every locale was invented fresh, so the name has to carry the
difference once the locales are real.

## Declared executives

Which state-wide offices a locale has, and who fills them, is declared per locale rather than held as a constant inside the refresher that reads them.

The executives list began as a constant inside the Maryland refresher, so the
second state to adopt that refresher was handed Maryland's Governor. The same
shape reached three other facts a refresher used to know about itself — its own
jurisdiction name among them — which is why a refresher now derives every one of
them from the locale it was given, and its upload path with them, rather than
naming any of them itself.

Dispatch follows the same rule. Which vote source a locale reads is taken from
its own declaration and not from what kind of locale it is, so stubbing
`congress?` or `local?` in a test can no longer change where a fetch goes.

### A stored portrait address keeps no query string

The executive portraits are stored as the address up to the "?" and no further.

The site serving them hands out addresses whose query string stops working
after ten minutes, so storing the whole thing stores an expiry. Everything
before the "?" resolves on its own, which is what makes it worth keeping.

## Published legislator votes

publishes_legislator_votes describes the publisher's evidence, not whether a locale is a city. Congress and Maryland declare true; Baltimore declares false.

The Baltimore investigation found no roll call among 200 matters. Its score
therefore uses organization disagreement and recency without a legislator-vote
margin. Sponsorship-based inferred votes do not establish a published roll
call. A city that publishes individual votes can declare true and use the full
signal set described in [[bill-interesting-score]].

### The vote fetchers are one interface chosen at run time

The Maryland fetcher and the two OpenStates ones are picked at run time behind
one interface, so all three accept the same keyword names whether or not each
one reads every argument.

The OpenStates pair reads only the bill, because the vote number it would
otherwise need is not something that source supplies. Their shared connector is
never reached today — the fetcher raises before the request is made, since
Maryland uses its own — and it is kept reading its credential through the
ordinary secret path anyway, so that it is already correct the day the
connector is wired up rather than needing a change nobody remembers to make.

For generic or declarative sources, `GenericVoteAdapter` and `GenericRosterAdapter` unify vote extraction and roster fetching behind standardized configuration hashes, removing the need for jurisdiction-specific scraper classes when endpoints and field mappings are specified in jurisdiction rules.

## Declared bill chambers

bill_chambers defines the available chambers, and default_bill_chamber must belong to that list. These declarations prevent a Maryland bill from starting in a nonexistent council.

Baltimore declares only council. The Creator uses list membership to decide
which inputs apply, so a future city with a senate can expose those inputs.
An undeclared locale leaves the choice editable instead of guessing a chamber.

A new bill's starting chamber comes from the locale's own
`default_bill_chamber`. It used to be decided by asking whether the locale was
Congress and defaulting everything else to council, which was wrong for
Maryland, whose General Assembly has no council; it also left the
required-chamber check unreachable, because a value was always present. An
empty chamber now stays empty and the check can refuse it.

`bill_chambers` reads as null on props from a server that predates the field,
which a tab left open long enough will still be holding. A null is not a list,
so a membership test against it throws during render rather than falling
through to the undeclared case, and the reading code allows for that.

## Explicit retrieval and parsing decoupling

Integration rules separate transport retrieval from payload parsing. Opaque engine identifiers decouple into distinct retrieval and parsing properties.

Each domain rule block (`legislation_rules`, `hearings_rules`, `vote_rules`, `roster_rules`, `law_rules`) specifies `retrieval` to govern network acquisition or repository transport, and `parsing` to govern payload decoding and field mapping. Transitional compatibility falls back to `engine` when either property is omitted, enabling phased adapter migration without breaking existing locale configurations.

Roster evidence attribution properties (`evidence_publisher`, `evidence_jurisdiction`, `evidence_source_url`) identify upstream official authorities without hardcoding jurisdiction names in generic roster adapters. Similarly, vote execution properties (`enable_historical_fallback`, `timezone`) configure candidate retries and local calendar calculations directly per jurisdiction.

Eliminating legacy jurisdiction symbols such as `:maryland_general_assembly` and `:mga` ensures generic adapters (`GenericLegislationAdapter`, `GenericVoteAdapter`) route all HTML processing through generic protocols (`:generic_html`), while `determine_retrieval` maps declared jurisdiction rules without code mutations.

## Readiness Preflight Decoupling

The readiness preflight distinguishes between automatic retrieval capability and manual curation based on explicit configuration.

When `retrieval` and `parsing` are set to `curated`, the roster is considered manual unless `curated_readiness_check` is explicitly `true`. This decouples the mechanism of curation from the status of automatic refresh readiness, ensuring that locales without automated pipelines do not incorrectly report as ready for automatic updates.

## Data-driven legislative session configuration

Legislative sessions define temporal boundaries for legislation and representative terms directly within each SwayLocale's declarative YAML document.

Prior architecture embedded jurisdiction-specific session identifiers, convening calendars, and ordinal formats within individual adapter classes. This approach forced code changes whenever a new session convened and prevented arbitrary jurisdictions from participating in the generic legislation pipeline.

Defining `legislative_sessions` in `config/sway_locales/*.yml` allows `SwayLocale::DocumentReader` to parse, validate, and synchronize session records dynamically. Ingestion and generic adapters resolve session parameters dynamically: incoming bills are assigned to sessions covering their introduction date via `sway_locale.legislative_session_for_date`, while pipeline adapters query upstream endpoints using the active session's `upstream_name` (falling back to `name`) rather than hardcoded dates or jurisdiction-specific branching. HTML discovery uses the session-resolution boundary described in [[legislation-pipeline#The legislation pipeline#Upstream jurisdiction adapters]]; locale documents supply session records during synchronization rather than a discovery-time fallback.

## Strict Client Resolution and Fallback Eradication

Integration adapters mandate explicit client parameters within declared jurisdiction rules, rejecting implicit city or document reader fallbacks.

Under the data-driven architecture, generic pipeline adapters (`GenericLegislationAdapter` and `GenericHearingsAdapter`) decouple from hardcoded jurisdiction names by expecting explicit `jurisdiction` declarations inside locale YAML rules (`legislation_rules` and `hearings_rules`) or explicit `client` parameters in adapter configuration hashes. If a locale specifies a Legistar retrieval strategy without configuring `jurisdiction` or `client`, adapters fail immediately with `ArgumentError` rather than defaulting to `target_locale.city`.

This contract guarantees that jurisdiction mapping remains entirely data-driven and declared within `config/sway_locales/*.yml`. Service callers cannot inadvertently query the wrong municipality endpoint due to ambiguous fallback logic, and adding support for new jurisdictions requires zero modifications to adapter source code.

This boundary extends to upstream error isolation. By encapsulating vendor transport exceptions directly into `BillProcessingError` within generic adapters, pipeline fetch services remain insulated from integration-specific exception hierarchies.


