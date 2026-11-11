---
lat:
  mode: how-to
---
# Add a SwayLocale

This procedure describes onboarding a SwayLocale from a declarative YAML document. It produces a seeded SwayLocale with verified representative matching; unsupported automation remains visibly unavailable.

## Prepare the SwayLocale

Complete these four onboarding steps to configure and verify a new SwayLocale. Start with a working development installation and keep unsupported automation capabilities declared as unavailable.

1. Create `config/sway_locales/SLUG.yml` with the locale's identity (`city`, `region`, `country`, `time_zone`, `legislative_sessions`), seed attributes (`sample_address`, `icon_path`), source rules (`roster_source`, `roster_refresher`, `vote_source`, `law_source`, `hearings_source`), term rules (`cycle_anchor_year`, `cycle_years`, `identified_by`), and Nominatim geographic bounds (`nominatim_viewbox`, `nominatim_country_codes`). Declare unsupported automated fetchers or pipelines as `:unavailable`.
2. Supply `db/seeds/data/COUNTRY/REGION/CITY/legislators.json` in the declared preparer's format with supported person identities, names, party affiliations, and district numbers.
3. Configure boundary matching: install `storage/geojson/SLUG.geojson` containing polygon features whose `properties.area_name` values match district numbers, or configure external geocoding providers for state and federal boundaries.
4. Run `SwayLocale::ReadinessPreflight.check_file("config/sway_locales/SLUG.yml")` to verify document validity, file dependencies, and declared capability combinations before database ingestion.

## Seed and verify the SwayLocale

Execute the seeding workflow and run integration tests to confirm representative resolution and idempotent execution.

1. Run `dip run rails db:seed` or `SeedSwayLocale.run` to discover the YAML document, create or update the `SwayLocale` record, and record seed timestamps.
2. Seed the initial roster with `SeedLegislator.run([sway_locale])`. Verify that current representatives and district associations are correctly created from the data fixture.
3. Repeat the seeding operations to confirm idempotence: existing `SwayLocale` and `Legislator` records are preserved without duplication.
4. Verify resident address assignment against the configured GeoJSON polygon or geocoder, ensuring residents match their district representatives.
5. Confirm that automatic background jobs, such as `RefreshLegislatorsCacheJob`, gracefully skip when `roster_refresher` is `:unavailable`.
