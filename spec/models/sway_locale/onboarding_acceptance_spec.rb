# frozen_string_literal: true

require "rails_helper"
require Rails.root.join("db", "seeds", "models", "sway_locale")
require Rails.root.join("db", "seeds", "models", "legislator")

RSpec.describe "SwayLocale declarative onboarding acceptance", type: :model do
  it "proves onboarding a 4th SwayLocale via YAML without touching shared registries" do
    annapolis_slug = "annapolis-maryland-united_states"
    yaml_path = Rails.root.join("config", "sway_locales", "#{annapolis_slug}.yml").to_s

    # 1. Discovery through DocumentReader
    expect(File.exist?(yaml_path)).to be(true)
    doc = SwayLocale::DocumentReader.fetch(annapolis_slug)
    expect(doc.city).to eq("annapolis")
    expect(doc.region).to eq("maryland")
    expect(doc.name).to eq(annapolis_slug)

    # 2. Dynamic registry resolution
    expect(SwayLocale::JurisdictionRulesRegistry.declared?(annapolis_slug)).to be(true)
    j_rules = SwayLocale::JurisdictionRulesRegistry.fetch(annapolis_slug)
    expect(j_rules.roster_rules&.[](:retrieval)).to eq("curated")
    expect(j_rules.roster_rules&.[](:parsing)).to eq("curated")
    expect(j_rules.vote_rules&.[](:retrieval)).to eq("manual")
    expect(j_rules.vote_rules&.[](:parsing)).to eq("manual")
    expect(j_rules.publishes_legislator_votes).to be(false)
    expect(j_rules.chamber_label).to eq("City Council")
    expect(j_rules.law_rules&.[](:retrieval)).to eq("unavailable")
    expect(j_rules.law_rules&.[](:parsing)).to eq("unavailable")
    expect(j_rules.respond_to?(:roster_source)).to be(false)
    expect(j_rules.respond_to?(:vote_source)).to be(false)

    expect(SwayLocale::TermRulesRegistry.declared?(annapolis_slug)).to be(true)
    t_rules = SwayLocale::TermRulesRegistry.fetch(annapolis_slug)
    expect(t_rules.cycle_anchor_year).to eq(2025)
    expect(t_rules.cycle_years).to eq(4)
    expect(t_rules.identified_by).to eq(:person)

    # 3. Readiness preflight
    preflight = SwayLocale::ReadinessPreflight.check_file(yaml_path)
    expect(preflight.ready?).to be(true)
    expect(preflight.manual_only?).to be(true)
    expect(preflight.roster_bootstrap_present).to be(true)
    expect(preflight.geography_present).to be(true)
    expect(preflight.errors).to be_empty

    # 4. Database seeding from YAML
    SeedSwayLocale.run
    sway_locale = SwayLocale.resolve_by_computed_name(annapolis_slug)
    raise "sway_locale not found" unless sway_locale

    expect(sway_locale.sample_street).to eq("160 Duke of Gloucester St")
    expect(sway_locale.sample_postal_code).to eq("21401")
    expect(sway_locale.sample_latitude).to be_within(0.0001).of(38.9784)
    expect(sway_locale.sample_longitude).to be_within(0.0001).of(-76.4922)

    # 5. Roster seeding from fixture
    expect { SeedLegislator.run([sway_locale]) }.not_to raise_error
    mayor = Legislator.find_by(external_id: "annapolis-mayor")
    expect(mayor).not_to be_nil
    expect(mayor&.first_name).to eq("Gavin")
    expect(mayor&.last_name).to eq("Buckley")
    expect(mayor&.title).to eq("Mayor")

    ward1_rep = Legislator.find_by(external_id: "annapolis-ward-1")
    expect(ward1_rep).not_to be_nil
    expect(ward1_rep&.first_name).to eq("Elly")
    expect(ward1_rep&.last_name).to eq("Tierney")

    # 6. Idempotent reseeding
    expect { SeedSwayLocale.run }.not_to raise_error
    expect { SeedLegislator.run([sway_locale]) }.not_to raise_error

    # 7. Local GeoJSON boundary matching
    return unless sway_locale

    expect(sway_locale.has_geojson?).to be(true)
    geojson_path = Rails.root.join("storage", "geojson", "#{sway_locale.name}.geojson")
    expect(File.exist?(geojson_path)).to be(true)
    geojson_raw = File.read(geojson_path)
    expect(geojson_raw).to include("1")

    # 8. Automated roster refresher skips gracefully
    allow(SwayLogging).to receive(:info)
    expect(SwayLogging).to receive(:info).with(
      "refresh_legislators_cache.unavailable_refresher",
      hash_including(sway_locale: annapolis_slug)
    )
    job = RefreshLegislatorsCacheJob.new
    expect(job.send(:refresher_for, sway_locale)).to be_nil
  end
end
