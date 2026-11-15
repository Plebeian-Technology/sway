# frozen_string_literal: true

require "rails_helper"

RSpec.describe DevelopmentAccountAddressService do
  describe ".resolve" do
    it "creates an address from the locale's sample address when none matches" do
      sway_locale = create(:sway_locale, :baltimore)
      expect(sway_locale.sample_street).to be_present
      expect(sway_locale.sample_postal_code).to be_present
      expect(sway_locale.sample_latitude).to be_present
      expect(sway_locale.sample_longitude).to be_present

      address_count = Address.count
      address = described_class.resolve(sway_locale: sway_locale)

      expect(Address.count).to eq(address_count + 1)
      expect(address).to be_persisted
      expect(address.street).to eq(sway_locale.sample_street)
      expect(address.postal_code).to eq(sway_locale.sample_postal_code)
      expect(address.region_code).to eq(sway_locale.region_code)
      expect(address.city).to eq("Baltimore")
      expect(address.latitude.to_f).to eq(sway_locale.sample_latitude.to_f)
      expect(address.longitude.to_f).to eq(sway_locale.sample_longitude.to_f)
      expect(address.normalized_key).to eq(
        Address.normalized_key_for(latitude: sway_locale.sample_latitude, longitude: sway_locale.sample_longitude)
      )
    end

    # @lat: [[personal-detail-encryption#Encrypting the personal details Sway keeps#An encrypted column cannot be a lookup key]]
    it "returns the same address on a second call without creating another" do
      sway_locale = create(:sway_locale, :baltimore)
      first = described_class.resolve(sway_locale: sway_locale)

      expect {
        expect(described_class.resolve(sway_locale: sway_locale).id).to eq(first.id)
      }.not_to change(Address, :count)
    end

    it "returns an existing address stored under the sample coordinates' normalized key" do
      sway_locale = create(:sway_locale, :baltimore)
      existing = create(
        :address,
        street: "1 Existing St",
        latitude: sway_locale.sample_latitude,
        longitude: sway_locale.sample_longitude,
        normalized_key: Address.normalized_key_for(
          latitude: sway_locale.sample_latitude,
          longitude: sway_locale.sample_longitude
        )
      )

      expect {
        expect(described_class.resolve(sway_locale: sway_locale).id).to eq(existing.id)
      }.not_to change(Address, :count)
    end

    it "raises naming the locale and sample_street when the sample street is blank" do
      sway_locale = create(:sway_locale, :baltimore)
      sway_locale.update!(sample_street: nil)

      expect {
        expect {
          described_class.resolve(sway_locale: sway_locale)
        }.to raise_error(RuntimeError, "Sway locale #{sway_locale.name} carries no sample address: sample_street blank")
      }.not_to change(Address, :count)
    end

    it "lists every blank sample column in column order" do
      sway_locale = create(:sway_locale, :baltimore)
      sway_locale.update!(sample_longitude: nil, sample_postal_code: nil)

      expect {
        expect {
          described_class.resolve(sway_locale: sway_locale)
        }.to raise_error(RuntimeError, /: sample_postal_code, sample_longitude blank\z/)
      }.not_to change(Address, :count)
    end

    %i[sample_street sample_postal_code sample_latitude sample_longitude].each do |column|
      it "raises when only #{column} is blank" do
        sway_locale = create(:sway_locale, :baltimore)
        sway_locale.update!(column => nil)

        expect {
          described_class.resolve(sway_locale: sway_locale)
        }.to raise_error(RuntimeError, /: #{column} blank\z/)
      end
    end
  end
end
