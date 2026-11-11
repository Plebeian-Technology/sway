---
lat:
  mode: reference
---
# Locale extension requirements

A functional SwayLocale needs identity, source declarations, term rules, representative data and address matching. Adding a row to locales.json alone does not provide those capabilities.

## Current configuration surfaces

Locale configuration is driven entirely by declarative YAML files in `config/sway_locales/`, eliminating jurisdiction-specific ruby files. The current procedure for adding a new locale is [[add-a-sway-locale]].

| Surface | Current responsibility |
| --- | --- |
| db/seeds/data/locales.json | Identity, legislative session date, timezone, icon URL |
| app/models/sway_locale/jurisdiction_rules_registry.rb | Roster, refresher, votes, legislation, law, hearings, chambers and provider identifiers |
| app/models/sway_locale/term_rules_registry.rb | Convening calendar, cycle, identity scheme and evidence capabilities |
| db/seeds/data/COUNTRY/REGION/CITY/legislators.json | Boot-time roster input in the declared preparer's format |
| storage/geojson/SLUG.geojson | Local representative assignment from district polygons |
| Admin Locales | Sample address for developer-account registration |
| config/sway_locales/SLUG.yml | Declarative locale attributes, source/term rules, and Nominatim bounds |
| app/models/sway_locale.rb (`SwayLocale#to_builder`) | Serialized locale attributes including Nominatim bounds for autocomplete |


## Work count

A compatible US state requires six backend deliverables; a maintained US city requires seven. These counts exclude app installation, optional developer setup, frontend source presentation and unsupported provider implementation.

- Six shared deliverables: seed metadata, SwayLocale declaration, term declaration, roster input, address matching, seed verification.
- The maintained-city seventh deliverable is a matching official roster refresher; the only municipal refresher currently reads Baltimore.
- Merely adding an empty locale row is one edit, but does not establish representative assignment or working imports.
- A fully automated locale has no universal fixed step count: discovery, bill text, hearings, law, roster refresh and legislative votes are separate provider capabilities.

## Seed limitations

Seed JSON contains fields that do not control their apparent features, while reusable roster preparers retain their original SwayLocale's calendar fallbacks.

- JSON id, districts and regionCode do not create those values; districts are derived from roster entries.
- Sample address values come from SeedSwayLocale::SAMPLE_ADDRESSES, which only declares Baltimore, rather than arbitrary JSON fields.
- A missing legislators.json raises during seeding. Planned official-source bootstrap removes this requirement without inventing people or blocking boot on network access.
- The curated preparer falls back to Baltimore's 2024 four-year cycle. OpenStates falls back to Maryland's 2023 four-year cycle. A supplied 2025 two-year declaration still produced 2024–2028 and 2023–2027 respectively in a standalone reproduction.
- Calendar calculations cannot establish exact service dates. [[current-legislator-term]] owns official evidence and historical-write safeguards.

## Provider limitations

Declaring a provider symbol does not establish support for another SwayLocale. The audited bill and hearing clients still selected Baltimore when given a second-city context.

| Capability | Additional extension work |
| --- | --- |
| Legistar bill discovery | Pass the selected namespace; declare accepted matter types instead of requiring Ordinance and excluding Resolution |
| Legistar hearing discovery | Pass the selected namespace through FetchHearingsService |
| Legistar vote updates | Separate Baltimore sponsor inference from genuine roll calls; declare final-passage action identifiers |
| Other OpenStates state votes | Generic scraper explicitly raises NotImplementedError outside Maryland |
| Full law pipeline | Only Baltimore, Maryland and US law adapters exist; unrelated locales cannot borrow those corpora |
| New municipal roster | BaltimoreRefresh is city-specific; no explicit manual/unavailable refresher mode exists |
| New source family | Separate discovery, bill-text, hearing, law and vote implementations as applicable |

## Client presentation

Locale pickers, routes and most display names use server-provided data. Source-link presentation has remaining fixed lists.

- Web BillContent reads a fixed source-label map without an unknown-locale fallback, producing an unnamed icon-only link for another locale.
- Mobile already provides a generic label, but its source-host allowlist rejects new government domains. Legistar subdomains are already accepted.
- LocaleFlag hides missing artwork; a flag is optional, not a prerequisite for registration.
- Pipeline stage copy names Baltimore law for every locale. Provisional web voting copy names Maryland regardless of SwayLocale.

## Geography limits

Address membership currently derives a city, a US state and US Congress. An arbitrary geographic hierarchy is not expressed by a locale seed row.

- Counties, school districts, overlapping SwayLocales and non-US legislative tiers require a membership-resolution contract beyond Address.sway_locale_attribute_sets_for.
- Regional registration always uses OpenStates people.geo and matches its person IDs, regardless of the declared roster source.
- US state-code tables constrain seed preparers. Congressional districts use the US Census service.
- Seed and geocode readers strip non-digits from district identifiers; 1A and 1B cannot remain distinct. This is separate from multiple elected seats within one district.
- A replacement installation without Baltimore fails the development seed's explicit Baltimore lookup. The default locale also selects US Congress.

## Planned declarative contract

Each SwayLocale owns one YAML file at config/sway_locales/SLUG.yml. That file supplies seed attributes, source rules and term rules through the existing runtime reader interfaces.

- Files are discovered automatically in deterministic filename order. Adding a SwayLocale requires no shared list, locales.json append or Ruby registry entry.
- Each file contains exactly one SwayLocale. Its filename matches the normalized city-region-country slug; duplicate identities and mismatches are rejected before writes.
- The three bundled SwayLocales migrate into separate YAML files. locales.json ceases to be a runtime configuration source after consumer migration.
- New configuration fields and abstractions use SwayLocale terminology, with sway_locale in code and data keys. Existing source identifiers cited in this audit retain their actual spelling.
- Large geography or fixture assets remain separate files referenced by the SwayLocale configuration where needed.
- A shared parser precedes migration of each consumer. Provider and calendar classes remain allowlisted code, rather than arbitrary names instantiated from YAML.
- Explicit unavailable capabilities permit honest manual curation; unsupported automation refuses before a network request or write.
- A locale preflight reports missing geography, invalid source declarations, unavailable providers and incomplete configuration together.
- Official roster bootstrap and historical correction safeguards retain their existing ownership. A locale document never authorizes invented officials or dates.
- A fourth SwayLocale acceptance scenario must prove onboarding by adding its YAML file plus required assets, without modifying a shared list or core registry code.
- Legislative sessions are declared under the `legislative_sessions` key as a list of session mappings with `name`, `start_date`, `end_date`, `active`, and optional `upstream_name` attributes, loaded and validated dynamically by `SwayLocale::DocumentReader` and synced to `LegislativeSession` models; legacy start date fields have been eradicated; icon_url is a project-root relative path, documented in config/sway_locales/locale.example.yml.
- Newsroom sources are declared under the required `news_sources` key as a list of mappings with `url` and `path_policy` (`search_hint` or `restrict`), validated by `SwayLocale::DocumentReader` with deterministic `source_config_digest` computation and synchronized to `LlmBillSummarizationInstruction` database rows.
- [[app/models/sway_locale/document_reader.rb|SwayLocale::DocumentReader.discover]] caches deeply frozen `Document` arrays per directory keyed by each YAML file's path, `mtime` (seconds and nanoseconds), and byte size (bypassing the cache when `.read` is stubbed), and [[app/models/sway_locale.rb#SwayLocale#document]] and [[app/models/sway_locale.rb#SwayLocale#declared_jurisdiction_rules]] memoize their resolved values (including `nil` for undeclared locales) keyed on [[app/models/sway_locale.rb#SwayLocale#name]].

## Configurable membership resolution

Membership resolution associates a physical address with each governing SwayLocale through declared resolver strategies rather than a static three-tier city, state and congress tuple.

- Resolver strategies declared per SwayLocale:
  - `:local_polygon`: Point-in-polygon containment against `storage/geojson/SLUG.geojson` for municipal city council wards.
  - `:census_tigerweb`: US Census Bureau TigerWeb geocoding service for congressional districts (`congress-congress-united_states`).
  - `:open_states_geo`: OpenStates `people.geo` geocoding endpoint for US state legislative districts (`maryland-maryland-united_states`).
  - `:unavailable`: Explicit refusal for manually curated locales without automated geocoding; requires manual district assignment.
- Multi-tier and overlapping jurisdictions:
  - An address resolves against all configured SwayLocales whose boundaries contain the address.
  - Resolvers operate independently: failure or absence of an automated resolver in one tier does not invalidate membership in overlapping tiers.
  - County, school district, regional authority, and non-US locales declare explicit resolver capabilities without altering at-large seat ownership.
- Unsupported tiers:
  - Non-US locales or jurisdictions lacking polygon or geocoding APIs declare `:unavailable`; synthetic geocoding is prohibited.

## Lossless district identifier representation

District representation preserves alphanumeric subdistricts and non-numeric ward identifiers as lossless canonical strings without collapsing distinct seats.

- Canonical identifier format:
  - Stored and compared as an alphanumeric string (`"1A"`, `"1B"`, `"14"`, `"0"` for at-large).
  - Database compatibility: Existing `districts.name` column format (`"MD1"`, `"BC1"`) is preserved without mutating existing rows or user voter links.
  - New composite names concatenate region code and canonical district code (`"#{region_code}#{district_code}"`, e.g. `"MD1A"`).
- Code changes and deprecation paths:
  - `District#district_code` provides the lossless string identifier (`"1A"`, `"1B"`).
  - `District#number` is retained as a compatibility reader returning digits only or integer approximation where callers require numeric sorting.
  - `District#region_code` resolves from the associated `sway_locale.region_code` rather than stripping non-alphabetic characters from the composite name.
  - Seed preparers (`Base`, `OpenStates`, `Sway`) and geocode polygon matchers (`RGeo::GeoJSON::Feature#district`) preserve string identifiers without stripping non-digits.
- Seat identity separation:
  - Distinct elected seats within a shared district remain governed by `LegislatorIdentity` and are not conflated with geographic district boundaries.

## Default locale selection

The default locale is the final request fallback; development account seeds choose their locale separately.

- The final fallback in [[app/models/sway_locale.rb#SwayLocale]] returns the Congress locale when present and `nil` otherwise; [[request-locale-selection]] owns request precedence.
- In development, [[db/seeds.rb]] requires Baltimore for the primary admin and resolves its sample address through [[app/services/development_account_address_service.rb#DevelopmentAccountAddressService]]. The admin's registration contract is [[identity-and-access#Identity and access#The stand-in account borrows a jurisdiction's sample address#The primary development admin registers in Baltimore only]].
- The phone-verification shortcut uses the configured development locale, which defaults to Baltimore, through [[app/services/skip_phone_verification_provisioner.rb#SkipPhoneVerificationProvisioner]] and [[lib/sway/settings/dev_login.rb#DevLogin]]. Its separate account policy is [[identity-and-access#Identity and access#The stand-in account borrows a jurisdiction's sample address#The bypass skips SMS, not address registration]].

## Legislative session schema and validations

Legislative sessions define temporal governing intervals for bills and score calculations across SwayLocales.

- Attributes declared per session entry in `config/sway_locales/SLUG.yml`:
  - Allowed fields: `name`, `start_date`, `end_date`, `active`, `upstream_name`.
  - `name`: Unique alphanumeric session identifier string (e.g. `"119th Congress"` or `"2025 Regular Session"`).
  - `upstream_name`: String identifier used by upstream legislative APIs (e.g. `"2024RS"` or `"118"`), falling back to `name` when omitted or blank.
  - `start_date`: ISO 8601 calendar date when the session begins (`YYYY-MM-DD`).
  - `end_date`: ISO 8601 calendar date on or after `start_date` when the session concludes.
  - `active`: Boolean indicating whether the session is currently governing active legislation.
- Validation and schema rules in `SwayLocale::DocumentReader`:
  - Optional `legislative_sessions` list: when present, must be an array of mappings with only allowed fields.
  - Required fields per entry: `name`, `start_date`, `end_date`.
  - Date formats must be valid ISO 8601 strings or dates, and date ranges cannot invert (`end_date >= start_date`).
  - Session names must be unique within the locale.
  - At least one active session must be declared per locale document declaring sessions.
  - `DocumentReader#sync_legislative_sessions!(sway_locale)` synchronizes declared sessions to `LegislativeSession` rows during seeding, executing in `SeedSwayLocale#seed` even when scalar `SwayLocale` attributes are skipped by the hand-edit guard; database sessions omitted from YAML configuration are strictly hard-deleted (`destroy_all`) with dependent bill associations nullified (`on_delete: :nullify`).
- Active query scopes and methods on `LegislativeSession`:
  - `LegislativeSession.active`: Returns sessions currently marked active (`where(active: true)`).
  - `LegislativeSession.containing_date(date)`: Resolves sessions whose interval spans the target date (`start_date <= date AND end_date >= date`).
- `SwayLocale` session associations and query methods:
  - `has_many :legislative_sessions, inverse_of: :sway_locale, dependent: :destroy`.
  - `has_one :current_legislative_session, -> { where(active: true).order(start_date: :desc) }`.
  - `SwayLocale#legislative_session_for_date(date)`: Resolves `legislative_sessions.containing_date(target_date).order(start_date: :desc).first`.
  - `SwayLocale#current_legislative_session_start_date`: Delegates to `current_legislative_session&.start_date` after column removal (aliased as `current_session_start_date`).
- `Bill` session integration:
  - `belongs_to :legislative_session, optional: true`.
  - `Bill.current_legislative_session(sway_locale = nil)` / `Bill.current_session`: Filters by the active legislative session, falling back to `introduced_date_time_utc` bounding bounds when `legislative_session_id` is nil.
  - `Bill#active`: Delegates to `legislative_session.active?` when associated.

## News source schema and validations

News sources define authoritative publisher domains and path policies governing discovery and citations for bills across SwayLocales.

- Attributes declared per source entry in `config/sway_locales/SLUG.yml`:
  - Required fields: `url`, `path_policy`.
  - Allowed fields: `url`, `path_policy`.
  - `url`: Mandatory HTTPS publisher or section URL string.
  - `path_policy`: Allowed values: `"search_hint"`, `"restrict"`.
- Validation and schema rules in `SwayLocale::DocumentReader`:
  - Required `news_sources` list: must be an array of mappings; empty array (`[]`) explicitly disables discovery for that locale.
  - Scheme must be HTTPS; non-HTTPS schemes fail validation.
  - Userinfo and credentials (`@`) fail validation.
  - Custom ports fail validation; port 443 (including zero-padded `:0443`) is stripped.
  - IP literals across all formats (IPv4 standard, octal, hex, dword, shorthand, and IPv6) fail validation.
  - Local and private destinations (`localhost`, `.local`, `.internal`, `.lan`, `.home`, `.home.arpa`, `.corp`, `.localdomain`, single-label) fail validation.
  - All-numeric (`.123`, `.0`) and 0x-prefixed (`.0x12`) top-level domains fail validation under RFC 1123 §2.1 and RFC 3696 §2.
  - Canonicalization lowercases scheme and host, normalizes empty root path to `"/"`, and preserves non-root paths and trailing slashes.
  - Duplicate URLs after canonicalization fail validation.
- Digest and synchronization behavior:
  - `DocumentReader#source_config_digest` (aliased as `news_sources_digest`): Deterministic SHA256 digest of canonicalized sources sorted by URL.
  - `LlmBillSummarizationInstruction#news_sources`: Reads from authoritative locale document when present, falling back to legacy projection URLs.
  - `LlmBillSummarizationInstruction#allowed_domains`: Derives filtered domains exclusively from authoritative locale document sources.
## Nominatim geographic configuration

SwayLocale declarations in `config/sway_locales/SLUG.yml` supply Nominatim geographic bounding parameters to constrain address autocomplete suggestions to the locale's jurisdiction.

- `nominatim_viewbox`: Bounding box string formatted as `"min_lon,max_lat,max_lon,min_lat"` (left,top,right,bottom coordinates).
- `nominatim_country_codes`: ISO 3166-1 alpha-2 comma-delimited country code string (e.g. `"us"`).
- `nominatim_bounded`: Boolean flag indicating whether results outside the viewbox are strictly excluded (`true` or `false`).
- Runtime delivery: Serialized via `SwayLocale#to_builder` and typed in `ISwayLocale` for consumption by `useNominatimAddressAutocomplete`.
- Upstream compliance: Client requests include an identifying User-Agent header and throttle query dispatch with >= 1000ms debounce.
- Rollback path: Google Maps Places autocomplete files ([[app/frontend/components/user/AddressAutocomplete.tsx#AddressAutocomplete|AddressAutocomplete]], [[app/frontend/hooks/useAddressAutocomplete.ts#useAddressAutocomplete|useAddressAutocomplete]], and [[app/frontend/sway_utils/parseGoogleAddressComponents.ts#parseGoogleAddressComponents|parseGoogleAddressComponents]]) remain installed as a rollback path, while registration uses [[app/frontend/components/user/NominatimAddressAutocomplete.tsx#NominatimAddressAutocomplete|NominatimAddressAutocomplete]].
- Frontend integration: Rendered via `NominatimAddressAutocomplete` on the user-facing `SwayRegistration` Inertia page.

