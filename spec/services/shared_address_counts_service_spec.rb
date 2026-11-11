# frozen_string_literal: true

require "rails_helper"

RSpec.describe SharedAddressCountsService do
  it "excludes an address given by only one registered user" do
    address = create(:address)
    create(:user_address, user: create(:user), address:)

    expect(described_class.rows).to eq([])
  end

  # @lat: [[identity-and-access#A user holds one address]]
  it "counts the distinct users at one address" do
    address = create(:address)
    create(:user_address, user: create(:user), address:)
    create(:user_address, user: create(:user), address:)

    expect(described_class.rows).to eq([{address_ids: [address.id], user_count: 2}])
  end

  it "combines two address rows that share a normalized key into one row, listing both ids" do
    building = create(:address)
    duplicate_spelling = create(:address)
    building.update_column(:normalized_key, "shared-key")
    duplicate_spelling.update_column(:normalized_key, "shared-key")

    create(:user_address, user: create(:user), address: building)
    create(:user_address, user: create(:user), address: duplicate_spelling)

    expect(described_class.rows).to eq(
      [{address_ids: [building.id, duplicate_spelling.id].sort, user_count: 2}]
    )
  end

  it "does not combine two addresses that both have no normalized key yet" do
    one = create(:address)
    two = create(:address)

    create(:user_address, user: create(:user), address: one)
    create(:user_address, user: create(:user), address: two)

    expect(described_class.rows).to eq([])
  end

  it "sorts shared addresses by descending user count and never returns street or coordinate fields" do
    small = create(:address)
    small.update_column(:normalized_key, "small-key")
    create(:user_address, user: create(:user), address: small)
    create(:user_address, user: create(:user), address: small)

    large = create(:address)
    large.update_column(:normalized_key, "large-key")
    3.times { create(:user_address, user: create(:user), address: large) }

    rows = described_class.rows

    expect(rows).to eq(
      [{address_ids: [large.id], user_count: 3}, {address_ids: [small.id], user_count: 2}]
    )
    rows.each { |row| expect(row.keys.sort).to eq(%i[address_ids user_count]) }
  end
end
