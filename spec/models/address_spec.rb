# frozen_string_literal: true

# == Schema Information
#
# Table name: addresses
# Database name: primary
#
#  id                      :integer          not null, primary key
#  city                    :string           not null
#  country                 :string           default("US"), not null
#  geocode_abandoned_at    :datetime
#  geocode_next_attempt_at :datetime
#  latitude                :string
#  longitude               :string
#  normalized_key          :string
#  place_types             :json             not null
#  postal_code             :string           not null
#  region_code             :string           not null
#  street                  :string           not null
#  street2                 :string
#  street3                 :string
#  created_at              :datetime         not null
#  updated_at              :datetime         not null
#
# Indexes
#
#  index_addresses_on_normalized_key  (normalized_key)
#

RSpec.describe Address, type: :model do
  include ActiveSupport::Testing::TimeHelpers

  describe "#geocode" do
    let(:address) do
      Address.new(
        street: Faker::Address.street_address(include_secondary: false),
        city: Faker::Address.city,
        region_code: Faker::Address.state_abbr,
        postal_code: Faker::Address.postcode
      )
    end

    context "when an address is created with either no latitude, no longitude or neither" do
      it "sets the latitude and longitude of the address" do
        expect(address.latitude).to be_nil
        expect(address.longitude).to be_nil

        address.validate!

        expect(address.latitude).to be_truthy
        expect(address.longitude).to be_truthy
      end
    end

    context "when the production callback geocodes after commit" do
      def raw(address, column)
        ActiveRecord::Base.connection.select_value("SELECT #{column} FROM addresses WHERE id = #{address.id}")
      end

      typed_fields = {street: "100 N Holliday St", city: "Baltimore", region_code: "MD", postal_code: "21202"}

      before do
        allow(Rails.env).to receive(:test?).and_return(false)
        allow(SwayLogging).to receive(:log_exception)
        allow(SwayLogging).to receive(:warn)
        allow(Sentry).to receive(:capture_exception)
        allow(Sentry).to receive(:capture_message)
        allow(Geocoder).to receive(:search).and_return(
          [
            Geocoder::Result::Test.new(
              "coordinates" => [39.29105, -76.61069],
              "city" => "Baltimore",
              "state" => "Maryland",
              "state_code" => "MD",
              "postal_code" => "21202",
              "country_code" => "US",
              "types" => ["street_address"],
              "partial_match" => false
            )
          ]
        )
      end

      it "saves the coordinates as ciphertext" do
        address = Address.create!(**typed_fields)

        reloaded = Address.find(address.id)
        expect(reloaded.latitude.to_f).to eq(39.29105)
        expect(reloaded.longitude.to_f).to eq(-76.61069)
        expect(raw(address, "latitude")).not_to eq("39.29105")
        expect(raw(address, "longitude")).not_to eq("-76.61069")
      end

      it "leaves the normalized key nil, so a stranger's picked place cannot match the row" do
        address = Address.create!(**typed_fields, street2: "Apt 4")

        expect(Address.find(address.id).located?).to be(true)
        expect(Address.find(address.id).normalized_key).to be_nil
      end

      context "when the typed address has no city, region, postal code or country" do
        before do
          geocoded = Geocoder::Result::Test.new(
            "coordinates" => [39.2904, -76.6122],
            "city" => "baltimore",
            "state" => "Maryland",
            "state_code" => "md",
            "postal_code" => "21202",
            "country_code" => "us",
            "types" => ["street_address"],
            "partial_match" => false
          )
          allow(Geocoder).to receive(:search).and_return([geocoded])
        end

        it "fills each blank field from the geocode, normalized like a typed one" do
          address = Address.create!(
            street: "100 N Holliday St, Baltimore, MD 21202",
            city: "",
            region_code: "",
            postal_code: "",
            country: ""
          )

          reloaded = Address.find(address.id)
          expect(reloaded).to have_attributes(
            located?: true,
            city: "Baltimore",
            region_code: "MD",
            postal_code: "21202",
            country: "US"
          )
          expect(address).to have_attributes(city: "Baltimore", region_code: "MD", postal_code: "21202", country: "US")
          expect(reloaded.us_state_code).to eq("MD")
        end

        it "keeps every field the user typed" do
          address = Address.create!(
            street: "100 N Holliday St, Baltimore, MD 21202",
            city: "Towson",
            region_code: "",
            postal_code: "21204",
            country: ""
          )

          expect(Address.find(address.id))
            .to have_attributes(city: "Towson", region_code: "MD", postal_code: "21204", country: "US")
        end

        it "reads the state name when the geocode has no state code" do
          allow(Geocoder).to receive(:search).and_return(
            [
              Geocoder::Result::Test.new(
                "coordinates" => [39.29, -76.61],
                "state" => "Maryland",
                "state_code" => nil,
                "postal_code" => "21202",
                "types" => ["street_address"],
                "partial_match" => false
              )
            ]
          )

          address = Address.create!(
            street: "100 N Holliday St, Baltimore, MD 21202",
            city: "",
            region_code: "",
            postal_code: "",
            country: ""
          )

          expect(Address.find(address.id)).to have_attributes(city: "", region_code: "MD", postal_code: "21202", country: "")
        end

        it "locates an address anchored by city and state when the postal code is blank" do
          address = Address.create!(
            street: "100 N Holliday St",
            city: "Baltimore",
            region_code: "MD",
            postal_code: "",
            country: ""
          )

          reloaded = Address.find(address.id)
          expect(reloaded.located?).to be(true)
          expect(reloaded.postal_code).to eq("21202")
        end

        it "leaves a street-only address unlocated when the result is in another city and state" do
          allow(Geocoder).to receive(:search).and_return(
            [
              Geocoder::Result::Test.new(
                "coordinates" => [39.7817, -89.6501],
                "city" => "Springfield",
                "state" => "Illinois",
                "state_code" => "IL",
                "postal_code" => "62701",
                "country_code" => "US",
                "types" => ["street_address"],
                "partial_match" => false
              )
            ]
          )

          address = Address.create!(street: "123 Main St", city: "", region_code: "", postal_code: "", country: "")

          reloaded = Address.find(address.id)
          expect(reloaded).to have_attributes(located?: false, city: "", region_code: "", postal_code: "", country: "")
          expect(SwayLogging).to have_received(:warn)
            .with("address.geocode_untrusted", hash_including(address_id: address.id, reason: kind_of(String)))
          expect(Sentry).not_to have_received(:capture_exception)
          expect(Sentry).not_to have_received(:capture_message)
        end

        it "leaves the address unlocated when the result is a partial match" do
          allow(Geocoder).to receive(:search).and_return(
            [
              Geocoder::Result::Test.new(
                "coordinates" => [39.2904, -76.6122],
                "city" => "Baltimore",
                "state" => "Maryland",
                "state_code" => "MD",
                "postal_code" => "21202",
                "country_code" => "US",
                "types" => ["street_address"],
                "partial_match" => true
              )
            ]
          )

          address = Address.create!(street: "123 Main St", city: "", region_code: "", postal_code: "", country: "")

          reloaded = Address.find(address.id)
          expect(reloaded).to have_attributes(located?: false, city: "", region_code: "", postal_code: "", country: "")
          expect(Sentry).not_to have_received(:capture_exception)
          expect(Sentry).not_to have_received(:capture_message)
        end

        it "leaves the address unlocated when the result is only a route" do
          allow(Geocoder).to receive(:search).and_return(
            [
              Geocoder::Result::Test.new(
                "coordinates" => [39.2904, -76.6122],
                "city" => "Baltimore",
                "state" => "Maryland",
                "state_code" => "MD",
                "postal_code" => "21202",
                "country_code" => "US",
                "types" => ["route"],
                "partial_match" => false
              )
            ]
          )

          address = Address.create!(
            street: "100 N Holliday St, Baltimore, MD 21202",
            city: "",
            region_code: "",
            postal_code: "",
            country: ""
          )

          reloaded = Address.find(address.id)
          expect(reloaded).to have_attributes(located?: false, city: "", region_code: "", postal_code: "", country: "")
          expect(Sentry).not_to have_received(:capture_exception)
          expect(Sentry).not_to have_received(:capture_message)
        end
      end

      [
        Geocoder::OverQueryLimitError.new("over limit"),
        Timeout::Error.new("execution expired"),
        SocketError.new("getaddrinfo failed"),
        Errno::ECONNREFUSED.new("connect(2) for maps.googleapis.com"),
        OpenSSL::SSL::SSLError.new("SSL_connect returned=1")
      ].each do |error|
        it "keeps the row unlocated and reports a #{error.class}" do
          allow(Geocoder).to receive(:search).and_raise(error)

          expect { Address.create!(**typed_fields) }.not_to raise_error

          reloaded = Address.sole
          expect(reloaded.located?).to be(false)
          expect(reloaded.normalized_key).to be_nil
          expect(SwayLogging).to have_received(:log_exception)
            .with("address.geocode_failed", exception: error, address_id: reloaded.id)
          expect(Sentry).to have_received(:capture_exception).with(error, extra: {address_id: reloaded.id})
        end
      end

      it "leaves the row unchanged when the geocoder finds nothing" do
        allow(Geocoder).to receive(:search).and_return([])
        expect { Address.create!(**typed_fields) }.not_to raise_error

        reloaded = Address.sole
        expect(reloaded.located?).to be(false)
        expect(reloaded.updated_at).to eq(reloaded.created_at)
        expect(Sentry).not_to have_received(:capture_exception)
      end

      it "does not look up an address that already has coordinates" do
        allow(Geocoder).to receive(:search).and_call_original

        Address.create!(**typed_fields, latitude: 39.3, longitude: -76.6)

        expect(Geocoder).not_to have_received(:search)
      end

      context "with the geocode retry schedule" do
        created_time = Time.zone.local(2026, 11, 14, 12, 0, 0)

        it "records a failed attempt without firing the geocode callback or changing updated_at" do
          address = travel_to(created_time) do
            allow(Geocoder).to receive(:search).and_return([])
            Address.create!(**typed_fields)
          end
          original_updated_at = address.updated_at
          calls = 0
          allow(Geocoder).to receive(:search) do
            calls += 1
            []
          end

          travel_to(created_time + 2.hours) { address.record_failed_geocode_attempt! }

          expect(calls).to eq(0)
          expect(address.reload.updated_at).to eq(original_updated_at)
          expect(address.geocode_next_attempt_at).to be_present
        end

        it "reports geocode_due? as true for nil or a past time and false for a future time or when abandoned" do
          address = travel_to(created_time) do
            allow(Geocoder).to receive(:search).and_return([])
            Address.create!(**typed_fields)
          end

          travel_to(created_time + 1.hour) do
            expect(address.geocode_due?).to be(true)

            address.update_columns(geocode_next_attempt_at: 1.minute.ago)
            expect(address.geocode_due?).to be(true)

            address.update_columns(geocode_next_attempt_at: 1.minute.from_now)
            expect(address.geocode_due?).to be(false)

            address.update_columns(geocode_next_attempt_at: nil)
            address.record_geocode_abandoned!
            expect(address.geocode_due?).to be(false)
          end
        end

        it "flips geocode_window_over? at exactly created_at plus 30 days" do
          address = travel_to(created_time) do
            allow(Geocoder).to receive(:search).and_return([])
            Address.create!(**typed_fields)
          end

          travel_to(created_time + 30.days - 1.second) do
            expect(address.geocode_window_over?).to be(false)
          end
          travel_to(created_time + 30.days) do
            expect(address.geocode_window_over?).to be(true)
          end
        end
      end
    end
  end

  describe "#sway_locale" do
    context "when an address accesses its sway_locale" do
      let(:address) do
        Address.new(
          street: Faker::Address.street_address(include_secondary: false),
          city: Faker::Address.city,
          region_code: Faker::Address.state_abbr,
          postal_code: Faker::Address.postcode
        )
      end

      it "returns a SwayLocale, creating it if necessary" do
        congress = SwayLocale.default_locale
        start_sway_locale_count = SwayLocale.count
        end_sway_locale_count =
          start_sway_locale_count +
          (
            if congress.blank?
              address.sway_locales.size
            else
              address.sway_locales.size - 1
            end
          )

        expect(SwayLocale.count).to eql(end_sway_locale_count)

        expect(address.sway_locales.present?).to be_truthy
      end
    end
  end

  describe ".sway_locale_attribute_sets_for" do
    it "names the United States in the Congress set whatever country was submitted" do
      sets = Address.sway_locale_attribute_sets_for(city: "Toronto", region_code: "ON", country: "Canada")

      expect(sets.last).to eq({city: "congress", state: "congress", country: "US"})
    end

    it "leaves out the city set when the city is blank" do
      sets = Address.sway_locale_attribute_sets_for(city: "", region_code: "VA", country: "US")

      expect(sets).to eq([
        {city: "Virginia", state: "VA", country: "US"},
        {city: "congress", state: "congress", country: "US"}
      ])
    end

    it "leaves out the city and state sets when the region is blank" do
      sets = Address.sway_locale_attribute_sets_for(city: "Toronto", region_code: "", country: "Canada")

      expect(sets).to eq([{city: "congress", state: "congress", country: "US"}])
    end

    it "gives the city and state sets the United States when the country is blank" do
      sets = Address.sway_locale_attribute_sets_for(city: "Richmond", region_code: "VA", country: "")

      expect(sets.pluck(:country)).to eq(%w[US US US])
    end
  end

  describe "#us_state_code" do
    def address_with_region(region_code:, country:)
      Address.new(street: "1 Main St", city: "Somewhere", region_code:, country:, postal_code: "00000")
    end

    ["US", "United States", ""].each do |country|
      it "returns VA for region VA and country #{country.inspect}" do
        expect(address_with_region(region_code: "VA", country:).us_state_code).to eq("VA")
      end
    end

    it "returns nil for region ON and country Canada" do
      expect(address_with_region(region_code: "ON", country: "Canada").us_state_code).to be_nil
    end

    it "returns nil for a blank region" do
      expect(address_with_region(region_code: "", country: "US").us_state_code).to be_nil
    end

    it "returns nil for region US" do
      expect(address_with_region(region_code: "US", country: "US").us_state_code).to be_nil
    end
  end

  describe "#located?" do
    it "is true when latitude and longitude are both present" do
      expect(Address.new(latitude: "38.9", longitude: "-77.0").located?).to be(true)
    end

    it "is false when either coordinate is missing" do
      expect(Address.new(latitude: "38.9", longitude: nil).located?).to be(false)
      expect(Address.new(latitude: nil, longitude: "-77.0").located?).to be(false)
    end
  end

  # The tidying moved into a before_validation hook. An empty Address no longer
  # blows up on a nil city or region_code, and values are cleaned up as they are
  # written.
  describe "write-side normalization" do
    it "does not raise when instantiated with no attributes" do
      expect { Address.new }.not_to raise_error
    end

    it "normalizes region_code and titleizes city before validation" do
      address = Address.new(street: "1 Main", city: "baltimore", region_code: "maryland", postal_code: "21201")
      address.valid?
      expect(address.region_code).to eq("MD")
      expect(address.city).to eq("Baltimore")
    end
  end

  # @lat: [[address-normalized-key]]
  describe ".normalized_key_for" do
    let(:latitude) { 39.29105 }
    let(:longitude) { -76.61069 }

    it "gives two spellings of one building the same key" do
      abbreviated = Address.new(street: "100 N Holliday St", city: "Baltimore", region_code: "MD",
        postal_code: "21202", latitude:, longitude:)
      spelled_out = Address.new(street: "100 N Holliday Street", city: "baltimore", region_code: "MD",
        postal_code: "21202", latitude:, longitude:)

      expect(abbreviated.computed_normalized_key).to eq(spelled_out.computed_normalized_key)
    end

    it "absorbs a geocode that differs below the rounding precision" do
      expect(Address.normalized_key_for(latitude: 39.291051, longitude: -76.610691))
        .to eq(Address.normalized_key_for(latitude: 39.291053, longitude: -76.610694))
    end

    it "keeps two units in one building apart" do
      expect(Address.normalized_key_for(latitude:, longitude:, street2: "Apt 4"))
        .not_to eq(Address.normalized_key_for(latitude:, longitude:, street2: "Apt 5"))
    end

    it "gives one unit written three ways the same key" do
      keys = ["Apt 4", "#4", "Unit 4"].map do |unit|
        Address.normalized_key_for(latitude:, longitude:, street2: unit)
      end

      expect(keys.uniq.length).to eq(1)
    end

    it "keeps a floor and a unit apart from the reverse" do
      expect(Address.normalized_key_for(latitude:, longitude:, street2: "Floor 2", street3: "Apt 4"))
        .not_to eq(Address.normalized_key_for(latitude:, longitude:, street2: "Apt 4", street3: "Floor 2"))
    end

    it "separates two buildings that share a postal code" do
      expect(Address.normalized_key_for(latitude:, longitude:))
        .not_to eq(Address.normalized_key_for(latitude: 39.2951, longitude: -76.6144))
    end

    it "has no key until the row is geocoded" do
      expect(Address.normalized_key_for(latitude: nil, longitude:)).to be_nil
      expect(Address.normalized_key_for(latitude:, longitude: nil)).to be_nil
    end
  end

  # @lat: [[address-place-classification]]
  describe "place_types" do
    it "reads as empty on a row that predates the column" do
      address = Address.new(street: "1 Main", city: "Baltimore", region_code: "MD", postal_code: "21201")

      expect(address.place_types).to eq([])
    end

    it "keeps the whole list Google returns rather than one judgement" do
      address = Address.new(street: "1 Main", city: "Baltimore", region_code: "MD", postal_code: "21201")
      address.place_types = ["subpremise", "premise", "street_address"]

      expect(address.place_types).to eq(["subpremise", "premise", "street_address"])
    end
  end

  # @lat: [[personal-detail-encryption#What is encrypted on an address]]
  describe "encrypted street columns" do
    def raw(address, column)
      ActiveRecord::Base.connection.select_value("SELECT #{column} FROM addresses WHERE id = #{address.id}")
    end

    it "stores all three street columns as ciphertext" do
      address = create(:address)
      address.update!(street: "100 N Holliday St", street2: "Apt 4", street3: "Rear")

      expect(raw(address, "street")).not_to eq("100 N Holliday St")
      expect(raw(address, "street2")).not_to eq("Apt 4")
      expect(raw(address, "street3")).not_to eq("Rear")
    end

    it "still reads the street back for the person who gave it" do
      address = create(:address)
      address.update!(street: "100 N Holliday St")

      expect(Address.find(address.id).street).to eq("100 N Holliday St")
    end

    it "gives one street different ciphertext each time, so rows cannot be grouped" do
      first = create(:address)
      second = create(:address)
      first.update!(street: "100 N Holliday St")
      second.update!(street: "100 N Holliday St")

      expect(raw(first, "street")).not_to eq(raw(second, "street"))
    end
  end

  # @lat: [[personal-detail-encryption#What is encrypted on an address]]
  describe "encrypted coordinates" do
    def raw(address, column)
      ActiveRecord::Base.connection.select_value("SELECT #{column} FROM addresses WHERE id = #{address.id}")
    end

    it "stores both coordinates as ciphertext" do
      address = create(:address)
      address.update!(latitude: 39.29105, longitude: -76.61069)

      expect(raw(address, "latitude")).not_to eq("39.29105")
      expect(raw(address, "longitude")).not_to eq("-76.61069")
    end

    it "keeps the precision the district lookup needs" do
      address = create(:address)
      address.update!(latitude: 39.29099283082182, longitude: -76.61057130320664)

      reloaded = Address.find(address.id)
      expect(reloaded.latitude.to_f).to eq(39.29099283082182)
      expect(reloaded.longitude.to_f).to eq(-76.61057130320664)
    end

    it "still builds a point for the district lookup" do
      address = create(:address)
      address.update!(latitude: 39.29105, longitude: -76.61069)

      point = Address.find(address.id).to_cartesian
      expect(point.x).to eq(-76.61069)
      expect(point.y).to eq(39.29105)
    end

    it "still computes the same normalized key from stored coordinates" do
      address = create(:address)
      address.update!(latitude: 39.29105, longitude: -76.61069)
      reloaded = Address.find(address.id)

      expect(reloaded.computed_normalized_key)
        .to eq(Address.normalized_key_for(latitude: 39.29105, longitude: -76.61069))
    end
  end

  describe "#us_state_code" do
    it "returns nil for non-US addresses even when region_code matches a US abbreviation" do
      address = build(:address, region_code: "MD", country: "CA")
      expect(address.us_state_code).to be_nil
    end

    it "returns nil when region_code is not a valid US state code" do
      address = build(:address, region_code: "US", country: "US")
      expect(address.us_state_code).to be_nil
    end
  end

  describe "#record_failed_geocode_attempt!" do
    it "backs off to roughly one day once past GEOCODE_HOURLY_WINDOW" do
      created = Time.zone.local(2026, 3, 1, 12, 0, 0)
      address = create(:address, created_at: created)
      later = created + Address::GEOCODE_HOURLY_WINDOW + 1.hour

      address.record_failed_geocode_attempt!(later)

      expected_floor = later + (1.day * (1 - Address::GEOCODE_JITTER_FRACTION))
      expected_ceiling = [later + (1.day * (1 + Address::GEOCODE_JITTER_FRACTION)), created + Address::GEOCODE_RETRY_WINDOW].min
      expect(address.reload.geocode_next_attempt_at).to be_between(expected_floor, expected_ceiling)
    end
  end
end
