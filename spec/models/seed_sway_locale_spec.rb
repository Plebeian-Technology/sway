# frozen_string_literal: true

require "rails_helper"
require Rails.root.join("db", "seeds", "models", "sway_locale")

RSpec.describe SeedSwayLocale do
  describe ".run" do
    it "creates a SwayLocale for each YAML configuration and stamps last_seeded_at == updated_at" do
      expect { described_class.run }.to change(SwayLocale, :count).by(SeedSwayLocale.read_locales.length)

      SwayLocale.find_each do |sway_locale|
        expect(sway_locale.last_seeded_at).not_to be_nil
        expect(sway_locale.last_seeded_at).to eq(sway_locale.updated_at)
      end
    end

    it "reads seed metadata and sample address directly from declarative YAML" do
      described_class.run

      baltimore = SwayLocale.find_by(city: "baltimore", state: "maryland", country: "united_states") #: SwayLocale
      expect(baltimore.time_zone).to eq("America/New_York")
      expect(baltimore.sample_street).to eq("100 N Holliday St")
      expect(baltimore.sample_postal_code).to eq("21202")
      expect(baltimore.sample_latitude).to eq(39.29105)
      expect(baltimore.sample_longitude).to eq(-76.61069)
    end

    # @lat: [[identity-and-access#The stand-in account borrows a jurisdiction's sample address]]
    it "gives Baltimore the sample address the Geocoder stub answers with" do
      described_class.run

      baltimore = SwayLocale.find_by(city: "baltimore", state: "maryland", country: "united_states") #: SwayLocale
      stub = Geocoder.search("100 N Holliday St, Baltimore, MD, 21202").first #: Geocoder::Result::Test

      expect(baltimore.sample_street).to eq(stub.street)
      expect(baltimore.sample_postal_code).to eq(stub.postal_code)
      expect([baltimore.sample_latitude, baltimore.sample_longitude]).to eq(stub.coordinates)
    end

    it "gives a sample address to the locale DEV_ACCOUNT_SWAY_LOCALE defaults to" do
      described_class.run

      default = with_env("DEV_ACCOUNT_SWAY_LOCALE" => nil) do
        Sway::Settings::DevLogin.new.dev_account_sway_locale #: String
      end

      expect(SwayLocale.resolve_by_computed_name(default)&.sample_street).to eq("100 N Holliday St")
    end

    it "leaves the sample address empty on a locale whose entry names none" do
      described_class.run

      congress = SwayLocale.find_by(city: "congress", state: "congress", country: "united_states") #: SwayLocale

      expect(congress.sample_street).to be_nil
      expect(congress.sample_latitude).to be_nil
    end

    it "is idempotent on a clean re-run (updated_at still equals last_seeded_at)" do
      described_class.run
      described_class.run

      SwayLocale.find_each do |sway_locale|
        expect(sway_locale.last_seeded_at).to eq(sway_locale.updated_at)
      end
    end

    it "seeds a newly added SwayLocale YAML file without editing locales.json or Ruby registries" do
      synthetic_doc = SwayLocale::DocumentReader::Document.new(
        {
          "schema_version" => 1,
          "city" => "annapolis",
          "region" => "maryland",
          "country" => "united_states",
          "name" => "annapolis-maryland-united_states",
          "current_legislative_session_start_date" => "2025-01-01",
          "time_zone" => "America/New_York",
          "icon_url" => "annapolis_logo.svg",
          "sample_address" => {
            "street" => "160 Duke of Gloucester St",
            "postal_code" => "21401",
            "latitude" => 38.9784,
            "longitude" => -76.4922
          },
          "source_rules" => {
            "roster_source" => "curated",
            "roster_refresher" => "unavailable",
            "vote_source" => "manual",
            "publishes_legislator_votes" => false,
            "chamber_label" => "City Council",
            "session_numbering" => "term_years",
            "default_bill_chamber" => "council",
            "bill_chambers" => ["council"]
          },
          "term_rules" => {
            "convening" => {"kind" => "fixed_day", "month" => 12, "day" => 1},
            "cycle_anchor_year" => 2025,
            "cycle_years" => 4,
            "roster_lists_only_current_legislators" => true,
            "publishes_term_history" => false,
            "publishes_exact_term_dates" => false,
            "identified_by" => "seat"
          }
        },
        filename: "annapolis-maryland-united_states.yml"
      )

      allow(SwayLocale::DocumentReader).to receive(:all).and_return(
        SwayLocale::DocumentReader.all + [synthetic_doc]
      )

      expect { described_class.run }.to change(SwayLocale, :count).by(4)

      annapolis = SwayLocale.find_by(city: "annapolis", state: "maryland", country: "united_states")
      expect(annapolis).not_to be_nil
      expect(annapolis.sample_street).to eq("160 Duke of Gloucester St")
      expect(annapolis.sample_postal_code).to eq("21401")
      expect(annapolis.icon_url).to eq("annapolis_logo.svg")
    end

    it "seeds legislative sessions defined in Congress YAML" do
      described_class.run

      congress = SwayLocale.find_by(city: "congress", state: "congress", country: "united_states") #: SwayLocale
      expect(congress).not_to be_nil

      sessions = congress.legislative_sessions.order(:start_date)
      expect(sessions.count).to eq(2)

      session_118 = sessions.find_by!(name: "118th Congress")
      expect(session_118).not_to be_nil
      expect(session_118.start_date).to eq(Date.parse("2023-01-03"))
      expect(session_118.end_date).to eq(Date.parse("2025-01-03"))
      expect(session_118.active).to be(false)

      session_119 = sessions.find_by!(name: "119th Congress")
      expect(session_119).not_to be_nil
      expect(session_119.start_date).to eq(Date.parse("2025-01-03"))
      expect(session_119.end_date).to eq(Date.parse("2027-01-03"))
      expect(session_119.active).to be(true)

      expect(congress.current_legislative_session).to eq(session_119)
    end

    it "authoritatively syncs legislative sessions on repeated runs, cleaning up unlisted sessions" do
      described_class.run
      congress = SwayLocale.find_by(city: "congress", state: "congress", country: "united_states") #: SwayLocale

      # Create an out-of-band unlisted session to ensure it is authoritatively cleaned up
      extra_session = create(:legislative_session, sway_locale: congress, name: "117th Congress", start_date: Date.new(2021, 1, 3), end_date: Date.new(2023, 1, 3))

      described_class.run

      expect(congress.legislative_sessions.count).to eq(2)
      expect { extra_session.reload }.to raise_error(ActiveRecord::RecordNotFound)

      # Verify timestamps invariant still holds
      SwayLocale.find_each do |sway_locale|
        expect(sway_locale.last_seeded_at).to eq(sway_locale.updated_at)
      end
    end

    it "seeds legislative sessions from a synthetic SwayLocale YAML document" do
      synthetic_doc = SwayLocale::DocumentReader::Document.new(
        {
          "schema_version" => 1,
          "city" => "annapolis",
          "region" => "maryland",
          "country" => "united_states",
          "name" => "annapolis-maryland-united_states",
          "current_legislative_session_start_date" => "2025-01-01",
          "time_zone" => "America/New_York",
          "icon_url" => "annapolis_logo.svg",
          "source_rules" => {
            "roster_source" => "curated",
            "roster_refresher" => "unavailable",
            "vote_source" => "manual",
            "publishes_legislator_votes" => false,
            "chamber_label" => "City Council",
            "session_numbering" => "term_years",
            "default_bill_chamber" => "council",
            "bill_chambers" => ["council"]
          },
          "term_rules" => {
            "convening" => {"kind" => "fixed_day", "month" => 12, "day" => 1},
            "cycle_anchor_year" => 2025,
            "cycle_years" => 4,
            "roster_lists_only_current_legislators" => true,
            "publishes_term_history" => false,
            "publishes_exact_term_dates" => false,
            "identified_by" => "seat"
          },
          "legislative_sessions" => [
            {
              "name" => "2025-2029 Council",
              "start_date" => "2025-12-01",
              "end_date" => "2029-12-01",
              "active" => true
            }
          ]
        },
        filename: "annapolis-maryland-united_states.yml"
      )

      allow(SwayLocale::DocumentReader).to receive(:all).and_return(
        SwayLocale::DocumentReader.all.reject { |d| d.name == "annapolis-maryland-united_states" } + [synthetic_doc]
      )

      expect { described_class.run }.to change(LegislativeSession, :count).by(8) # 2 congress + 2 baltimore + 3 maryland + 1 synthetic annapolis

      annapolis = SwayLocale.find_by(city: "annapolis", state: "maryland", country: "united_states") #: SwayLocale
      expect(annapolis.legislative_sessions.count).to eq(1)
      expect(annapolis.current_legislative_session&.name).to eq("2025-2029 Council")
    end

    it "syncs legislative sessions even when SwayLocale scalar attributes are skipped due to out-of-band edits" do
      described_class.run

      congress = SwayLocale.find_by!(city: "congress", state: "congress", country: "united_states") #: SwayLocale
      baltimore = SwayLocale.find_by!(city: "baltimore", state: "maryland", country: "united_states") #: SwayLocale
      maryland = SwayLocale.find_by!(city: "maryland", state: "maryland", country: "united_states") #: SwayLocale

      congress.legislative_sessions.destroy_all
      baltimore.legislative_sessions.destroy_all
      maryland.legislative_sessions.destroy_all

      stale_seeded_at = 2.hours.ago.change(usec: 0)
      recent_updated_at = 1.hour.ago.change(usec: 0)

      congress.update_columns(
        sample_street: "789 Out Of Band St",
        last_seeded_at: stale_seeded_at,
        updated_at: recent_updated_at
      )
      baltimore.update_columns(last_seeded_at: stale_seeded_at, updated_at: recent_updated_at)
      maryland.update_columns(last_seeded_at: stale_seeded_at, updated_at: recent_updated_at)

      described_class.run(force: false)

      congress.reload
      expect(congress.sample_street).to eq("789 Out Of Band St")
      expect(congress.last_seeded_at).to be_within(1.second).of(stale_seeded_at)
      expect(congress.updated_at).to be_within(1.second).of(recent_updated_at)
      expect(congress.updated_at).not_to eq(congress.last_seeded_at)

      baltimore.reload
      expect(baltimore.last_seeded_at).to be_within(1.second).of(stale_seeded_at)
      expect(baltimore.updated_at).to be_within(1.second).of(recent_updated_at)
      expect(baltimore.updated_at).not_to eq(baltimore.last_seeded_at)

      maryland.reload
      expect(maryland.last_seeded_at).to be_within(1.second).of(stale_seeded_at)
      expect(maryland.updated_at).to be_within(1.second).of(recent_updated_at)
      expect(maryland.updated_at).not_to eq(maryland.last_seeded_at)

      expect(congress.legislative_sessions.count).to eq(2)
      expect(congress.legislative_sessions.find_by(name: "119th Congress")).to be_present
      expect(congress.current_legislative_session&.name).to eq("119th Congress")

      expect(baltimore.legislative_sessions.count).to eq(2)
      expect(baltimore.legislative_sessions.find_by(name: "73rd City Council")).to be_present
      expect(baltimore.current_legislative_session&.name).to eq("73rd City Council")

      expect(maryland.legislative_sessions.count).to eq(3)
      expect(maryland.legislative_sessions.find_by(name: "2026 Regular Session")).to be_present
      expect(maryland.current_legislative_session&.name).to eq("2026 Regular Session")
    end
  end

  describe "skip guard" do
    include_examples "a seedable model",
      model_class: SwayLocale,
      factory_name: :sway_locale,
      natural_key_attrs: {city: "baltimore", state: "maryland", country: "united_states"},
      run_seeder: SeedSwayLocale.method(:run)
  end
end
