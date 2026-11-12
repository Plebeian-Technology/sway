# frozen_string_literal: true

require "rails_helper"

# @lat: [[personal-detail-encryption#Why the key backfill has to run before the street is encrypted]]
RSpec.describe "Production snapshot address normalized keys", :production_snapshot, type: :model do
  include_context "production snapshot (migrated)"

  it "leaves no address with coordinates holding a nil normalized key" do
    expect(Address.count).to be > 0

    unkeyed_with_coordinates = Address
      .where.not(latitude: nil)
      .where.not(longitude: nil)
      .where(normalized_key: nil)

    expect(unkeyed_with_coordinates).to be_empty
  end

  it "computes matching normalized keys for addresses with coordinates" do
    addresses_with_coordinates = Address
      .where.not(latitude: nil)
      .where.not(longitude: nil)

    expect(addresses_with_coordinates).not_to be_empty

    addresses_with_coordinates.each do |address|
      expect(address.normalized_key).to eq(address.computed_normalized_key)
    end
  end
end
