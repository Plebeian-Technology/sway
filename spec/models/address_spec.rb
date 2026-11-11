# frozen_string_literal: true

# == Schema Information
#
# Table name: addresses
# Database name: primary
#
#  id             :integer          not null, primary key
#  city           :string           not null
#  country        :string           default("US"), not null
#  latitude       :string
#  longitude      :string
#  normalized_key :string
#  place_types    :json             not null
#  postal_code    :string           not null
#  region_code    :string           not null
#  street         :string           not null
#  street2        :string
#  street3        :string
#  created_at     :datetime         not null
#  updated_at     :datetime         not null
#
# Indexes
#
#  index_addresses_on_normalized_key  (normalized_key)
#

RSpec.describe Address, type: :model do
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
end
