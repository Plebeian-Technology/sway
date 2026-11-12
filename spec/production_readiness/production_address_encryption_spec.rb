# frozen_string_literal: true

require "rails_helper"

# @lat: [[personal-detail-encryption#Converting the rows that already exist]]
RSpec.describe "Production snapshot address encryption", :production_snapshot, type: :model do
  include_context "production snapshot (migrated)"

  # @lat: [[personal-detail-encryption#What is encrypted on an address]]
  it "leaves no address holding plaintext in sensitive address columns" do
    expect(Address.count).to be > 0

    sensitive_columns = %w[street street2 street3 latitude longitude]
    rows = ActiveRecord::Base.connection.select_all(
      "SELECT id, street, street2, street3, latitude, longitude FROM addresses"
    )

    rows.each do |row|
      sensitive_columns.each do |column|
        value = row[column]
        next if value.nil?

        expect(value).to start_with('{"p":')
      end
    end
  end

  it "decrypts all addresses cleanly via Address model" do
    expect(Address.count).to be > 0

    Address.find_each do |address|
      expect(address.street).to be_present
      expect(address.latitude).to be_present
      expect(address.longitude).to be_present
    end
  end
end
