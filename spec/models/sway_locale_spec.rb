# frozen_string_literal: true

# == Schema Information
#
# Table name: sway_locales
# Database name: primary
#
#  id                           :integer          not null, primary key
#  city                         :string           not null
#  country                      :string           default("United States"), not null
#  icon_url                     :string
#  last_seeded_at               :datetime
#  latest_election_year         :integer          default(2024), not null
#  legislators_cache_fetched_at :datetime
#  region_name                  :string           not null
#  sample_latitude              :float
#  sample_longitude             :float
#  sample_postal_code           :string
#  sample_street                :string
#  time_zone                    :string
#  created_at                   :datetime         not null
#  updated_at                   :datetime         not null
#
# Indexes
#
#  index_sway_locales_on_city_and_region_name_and_country  (city,region_name,country) UNIQUE
#

RSpec.describe SwayLocale, type: :model do
  # A locale's name is built from its city, state and country rather than stored in a
  # column, so find_by(name:) fails with StatementInvalid. This finder compares against
  # the built name instead.
  describe ".resolve_by_computed_name" do
    it "returns the locale whose computed name matches" do
      sway_locale = create(:sway_locale, city: "baltimore", state: "MD", country: "United States")
      expect(SwayLocale.resolve_by_computed_name("baltimore-maryland-united_states")).to eq(sway_locale)
    end

    it "returns nil for an unknown name (without raising)" do
      create(:sway_locale, city: "baltimore", state: "MD", country: "United States")
      expect(SwayLocale.resolve_by_computed_name("nowhere-nostate-nocountry")).to be_nil
    end
  end

  describe ".declared" do
    it "includes declared locales and excludes undeclared locales" do
      baltimore = create(:sway_locale, :baltimore)
      bethesda = create(:sway_locale, city: "bethesda", state: "MD", country: "United States")

      expect(SwayLocale.declared).to include(baltimore)
      expect(SwayLocale.declared).not_to include(bethesda)
    end
  end

  describe "#name" do
    context "when #name is called" do
      it "constructs a name from the city, state and country names" do
        sway_locale =
          lambda do
            SwayLocale.new(
              city: "Baltimore",
              state: "Maryland",
              country: "United States"
            )
          end.call

        expect(sway_locale.name).to eq("baltimore-maryland-united_states")
      end

      it "constructs a name from the city, state code and country code" do
        sway_locale =
          lambda do
            SwayLocale.new(city: "Baltimore", state: "MD", country: "US")
          end.call

        expect(sway_locale.name).to eq("baltimore-maryland-united_states")
      end
    end

    # @lat: [[locale-name-is-derived#Which attributes the memo is keyed on]]
    context "when the attributes it is composed from change" do
      it "reports the new name after a city is reassigned" do
        sway_locale = SwayLocale.new(city: "Baltimore", state: "MD", country: "US")
        expect(sway_locale.name).to eq("baltimore-maryland-united_states")

        sway_locale.city = "Annapolis"

        expect(sway_locale.name).to eq("annapolis-maryland-united_states")
      end

      it "reports the normalized name after the before_validation callbacks run" do
        sway_locale = SwayLocale.new(city: "Baltimore", state: "MD", country: "US")
        sway_locale.name

        sway_locale.valid?

        expect([sway_locale.city, sway_locale.state, sway_locale.country])
          .to eq(%w[baltimore maryland united_states])
        expect(sway_locale.name).to eq("baltimore-maryland-united_states")
      end
    end
  end

  # Builds the {label:, value:} pair that every page shares with the frontend to fill
  # the locale dropdown. Congress gets the name the frontend shows rather than the
  # built one.
  describe "#to_select_option" do
    it "returns human_name label and id value for a city locale" do
      sway_locale = create(:sway_locale, city: "Baltimore", state: "MD", country: "US")

      expect(sway_locale.to_select_option).to eq(
        {label: "Baltimore, Maryland, United States", value: sway_locale.id}
      )
    end

    it "labels the congress locale U.S. Congress" do
      congress = create(:sway_locale, city: "congress", state: "congress", country: "US")

      expect(congress.to_select_option).to eq(
        {label: "U.S. Congress", value: congress.id}
      )
    end
  end

  describe "#short_name" do
    it "returns the titleized city for a city locale" do
      sway_locale = create(:sway_locale, city: "New York", state: "NY", country: "US")

      expect(sway_locale.short_name).to eq("New York")
    end

    it "returns the titleized region for a state locale" do
      sway_locale = create(:sway_locale, city: "new_jersey", state: "NJ", country: "US")

      expect(sway_locale.short_name).to eq("New Jersey")
    end

    it "returns U.S. Congress for the congress locale" do
      congress = create(:sway_locale, city: "congress", state: "congress", country: "US")

      expect(congress.short_name).to eq("U.S. Congress")
    end
  end

  describe "#load_geojson" do
    context "when a geojson file is requested" do
      it "loads the geojson file corresponding to its name" do
        sway_locale =
          lambda do
            SwayLocale.new(city: "Baltimore", state: "MD", country: "US")
          end.call

        expect(sway_locale.load_geojson).to be_truthy
      end
    end
  end

  # City, state and country are tidied up just before validation, not every time a
  # record is loaded. So reading a saved locale no longer rewrites its fields and marks
  # it as changed. The finder tidies its own arguments through
  # SwayLocale.normalize_attributes.
  describe "normalization" do
    it "does not mark a persisted locale dirty on load" do
      sway_locale = SwayLocale.find_or_create_by_normalized!(city: "Baltimore", state: "MD", country: "United States")
      expect(SwayLocale.find(sway_locale.id).changed?).to be(false)
    end

    it "find_or_create_by_normalized! normalizes city case and is idempotent" do
      args = {city: "Baltimore", state: "MD", country: "United States"}
      first = SwayLocale.find_or_create_by_normalized!(**args)
      expect(first.city).to eq("baltimore")

      expect { SwayLocale.find_or_create_by_normalized!(**args) }
        .not_to change { SwayLocale.count }
      expect(SwayLocale.find_or_create_by_normalized!(**args).id).to eq(first.id)
    end

    # @lat: [[locale-extension#Planned declarative contract]]
    # @lat: [[locale-extension#Locale extension requirements#Planned declarative contract]]
    it "is idempotent when called via SwayLocale.find_or_create_by_normalized! with mixed casing and codes" do
      first = described_class.find_or_create_by_normalized!(city: "Baltimore", state: "MD", country: "US")
      second = described_class.find_or_create_by_normalized!(city: "baltimore", state: "maryland", country: "united_states")

      expect(second.id).to eq(first.id)
    end

    it "returns the existing row to the caller that loses a creation race" do
      args = {city: "Baltimore", state: "MD", country: "US"}
      existing = described_class.find_or_create_by_normalized!(**args)
      allow(described_class).to receive(:find_or_create_by!).and_raise(ActiveRecord::RecordNotUnique)

      expect(described_class.find_or_create_by_normalized!(**args).id).to eq(existing.id)
    end

    it "raises the collision when no row exists after it" do
      allow(described_class).to receive(:find_or_create_by!).and_raise(ActiveRecord::RecordNotUnique)

      expect { described_class.find_or_create_by_normalized!(city: "Baltimore", state: "MD", country: "US") }
        .to raise_error(ActiveRecord::RecordNotUnique)
    end
  end

  describe "#legislative_sessions" do
    it "has_many :legislative_sessions" do
      sway_locale = create(:sway_locale, city: "session_city_1", state: "session_state_1", country: "United States")
      session1 = create(:legislative_session, sway_locale:, name: "Session 1", active: false)
      session2 = create(:legislative_session, sway_locale:, name: "Session 2", active: true)

      expect(sway_locale.legislative_sessions).to contain_exactly(session1, session2)
    end

    it "destroys associated legislative_sessions when sway_locale is destroyed (dependent: :destroy)" do
      sway_locale = create(:sway_locale, city: "destroy_city_1", state: "destroy_state_1", country: "United States")
      create(:legislative_session, sway_locale:, name: "Session 1")
      create(:legislative_session, sway_locale:, name: "Session 2")

      expect { sway_locale.destroy }.to change(LegislativeSession, :count).by(-2)
    end
  end

  describe "#current_legislative_session" do
    it "returns the session marked active: true" do
      sway_locale = create(:sway_locale, city: "curr_city_1", state: "curr_state_1", country: "United States")
      _inactive = create(:legislative_session, sway_locale:, name: "118th", active: false)
      active_session = create(:legislative_session, sway_locale:, name: "119th", active: true)

      expect(sway_locale.current_legislative_session).to eq(active_session)
    end

    it "returns nil when no session is active" do
      sway_locale = create(:sway_locale, city: "curr_city_2", state: "curr_state_2", country: "United States")
      create(:legislative_session, sway_locale:, name: "Historical 1", active: false)
      create(:legislative_session, sway_locale:, name: "Historical 2", active: false)

      expect(sway_locale.current_legislative_session).to be_nil
    end

    it "returns nil when no sessions exist for the locale" do
      sway_locale = create(:sway_locale, city: "curr_city_3", state: "curr_state_3", country: "United States")

      expect(sway_locale.current_legislative_session).to be_nil
    end

    it "does not return an active session belonging to another locale" do
      sway_locale1 = create(:sway_locale, city: "curr_city_4a", state: "curr_state_4a", country: "United States")
      sway_locale2 = create(:sway_locale, city: "curr_city_4b", state: "curr_state_4b", country: "United States")
      create(:legislative_session, sway_locale: sway_locale1, name: "Session L1", active: false)
      _other_active = create(:legislative_session, sway_locale: sway_locale2, name: "Session L2", active: true)

      expect(sway_locale1.current_legislative_session).to be_nil
    end

    it "reflects updates when active status changes after reloading" do
      sway_locale = create(:sway_locale, city: "curr_city_5", state: "curr_state_5", country: "United States")
      session1 = create(:legislative_session, sway_locale:, name: "Session 1", active: true)
      session2 = create(:legislative_session, sway_locale:, name: "Session 2", active: false)

      expect(sway_locale.current_legislative_session).to eq(session1)

      session1.update!(active: false)
      session2.update!(active: true)

      expect(sway_locale.reload.current_legislative_session).to eq(session2)
    end

    it "deterministically returns the active session with the most recent start_date when multiple are active" do
      sway_locale = create(:sway_locale, city: "curr_city_multi", state: "curr_state_multi", country: "United States")
      _earlier_session = create(:legislative_session, sway_locale:, name: "118th", start_date: Date.new(2023, 1, 3), end_date: Date.new(2025, 1, 3), active: true)
      later_session = create(:legislative_session, sway_locale:, name: "119th", start_date: Date.new(2025, 1, 3), end_date: Date.new(2027, 1, 3), active: true)

      expect(sway_locale.current_legislative_session).to eq(later_session)
    end
  end

  describe "legacy session start date fields removal" do
    it "does not respond to current_legislative_session_start_date or next_legislative_session_start_date" do
      sway_locale = build(:sway_locale)
      expect(sway_locale.respond_to?(:current_legislative_session_start_date)).to be false
      expect(sway_locale.respond_to?(:next_legislative_session_start_date)).to be false
      expect(sway_locale.respond_to?(:next_session_start_date)).to be false
    end

    it "responds to current_session_start_date and returns current_legislative_session start_date" do
      sway_locale = create(:sway_locale, city: "curr_date_city", state: "curr_date_state", country: "United States")
      session = create(:legislative_session, sway_locale:, name: "119th", start_date: Date.new(2025, 1, 3), active: true)

      expect(sway_locale.current_session_start_date).to eq(session.start_date)
    end
  end

  describe "nominatim geographic configuration" do
    describe "delegation to underlying YAML document" do
      it "reads nominatim fields from the underlying document for Baltimore" do
        baltimore = create(:sway_locale, city: "baltimore", state: "maryland", country: "united_states")

        expect(baltimore.nominatim_viewbox).to eq("-76.7114,39.3720,-76.5297,39.1972")
        expect(baltimore.nominatim_bounded).to be(true)
        expect(baltimore.nominatim_country_codes).to eq("us")
      end

      it "reads nominatim fields from the underlying document for Congress (null viewbox, unbounded)" do
        congress = create(:sway_locale, city: "congress", state: "congress", country: "united_states")

        expect(congress.nominatim_viewbox).to be_nil
        expect(congress.nominatim_bounded).to be(false)
        expect(congress.nominatim_country_codes).to eq("us")
      end

      it "returns nil without error when no underlying document exists" do
        custom_locale = SwayLocale.new(city: "nowhere", state: "nostate", country: "nocountry")

        expect(custom_locale.document).to be_nil
        expect(custom_locale.nominatim_viewbox).to be_nil
        expect(custom_locale.nominatim_bounded).to be_nil
        expect(custom_locale.nominatim_country_codes).to be_nil
      end

      it "memoizes nil document for undeclared locales without re-invoking DocumentReader.find, and invalidates when name changes" do
        custom_locale = SwayLocale.new(city: "austin", state: "texas", country: "united_states")

        expect(SwayLocale::DocumentReader).to receive(:find)
          .with("austin-texas-united_states")
          .once
          .and_call_original

        expect(custom_locale.document).to be_nil
        expect(custom_locale.document).to be_nil

        expect(SwayLocale::DocumentReader).to receive(:find)
          .with("baltimore-maryland-united_states")
          .once
          .and_call_original

        custom_locale.city = "baltimore"
        custom_locale.state = "maryland"
        expect(custom_locale.document).to be_present
        expect(custom_locale.document&.name).to eq("baltimore-maryland-united_states")
      end
    end

    describe "attribute writers for test overrides" do
      it "allows overriding nominatim_viewbox on an instance" do
        sway_locale = create(:sway_locale, city: "baltimore", state: "maryland", country: "united_states")
        sway_locale.nominatim_viewbox = "-75.0,38.0,-74.0,37.0"

        expect(sway_locale.nominatim_viewbox).to eq("-75.0,38.0,-74.0,37.0")

        sway_locale.nominatim_viewbox = nil
        expect(sway_locale.nominatim_viewbox).to be_nil
      end

      it "allows overriding nominatim_bounded on an instance" do
        sway_locale = create(:sway_locale, city: "baltimore", state: "maryland", country: "united_states")
        sway_locale.nominatim_bounded = false

        expect(sway_locale.nominatim_bounded).to be(false)

        sway_locale.nominatim_bounded = true
        expect(sway_locale.nominatim_bounded).to be(true)
      end

      it "allows overriding nominatim_country_codes on an instance" do
        sway_locale = create(:sway_locale, city: "baltimore", state: "maryland", country: "united_states")
        sway_locale.nominatim_country_codes = "ca,mx"

        expect(sway_locale.nominatim_country_codes).to eq("ca,mx")

        sway_locale.nominatim_country_codes = nil
        expect(sway_locale.nominatim_country_codes).to be_nil
      end
    end

    describe "#to_builder" do
      it "serializes nominatim fields into the builder attributes" do
        sway_locale = create(:sway_locale, city: "baltimore", state: "maryland", country: "united_states")
        builder_hash = sway_locale.to_builder.attributes!

        expect(builder_hash).to include(
          "nominatim_viewbox" => sway_locale.nominatim_viewbox,
          "nominatim_bounded" => sway_locale.nominatim_bounded,
          "nominatim_country_codes" => sway_locale.nominatim_country_codes
        )
      end

      it "reflects overridden attribute values in to_builder" do
        sway_locale = create(:sway_locale, city: "baltimore", state: "maryland", country: "united_states")
        sway_locale.nominatim_viewbox = "-70.0,40.0,-69.0,39.0"
        sway_locale.nominatim_bounded = false
        sway_locale.nominatim_country_codes = "gb"

        builder_hash = sway_locale.to_builder.attributes!

        expect(builder_hash["nominatim_viewbox"]).to eq("-70.0,40.0,-69.0,39.0")
        expect(builder_hash["nominatim_bounded"]).to be(false)
        expect(builder_hash["nominatim_country_codes"]).to eq("gb")
      end
    end
  end

  describe "#at_large_district" do
    it "returns the 0-numbered district without loading non-zero districts when districts are not preloaded" do
      sway_locale = create(:sway_locale, city: "at_large_city", state: "MD", country: "united_states")
      _district1 = create(:district, sway_locale:, name: "MD1")
      _district2 = create(:district, sway_locale:, name: "MD2")
      district0 = create(:district, sway_locale:, name: "MD0")

      fresh_locale = SwayLocale.find(sway_locale.id)
      expect(fresh_locale.districts.loaded?).to be(false)

      expect(fresh_locale.at_large_district).to eq(district0)
      expect(fresh_locale.districts.loaded?).to be(false)
    end

    it "prefers locale_wide_district_name over another non-digit district" do
      baltimore = create(:sway_locale, :baltimore)
      _other_district = create(:district, sway_locale: baltimore, name: "BaltimoreCityWide")
      md0 = create(:district, sway_locale: baltimore, name: "MD0")

      fresh_locale = SwayLocale.find(baltimore.id)
      expect(fresh_locale.at_large_district).to eq(md0)
    end
  end
end
