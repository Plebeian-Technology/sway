# frozen_string_literal: true

require "rails_helper"
require Rails.root.join("db", "data", "20261111000002_encrypt_address_details")

# @lat: [[personal-detail-encryption#Converting the rows that already exist]]
RSpec.describe "EncryptAddressDetails data migration", type: :model do
  let(:migration) { Object.const_get(:EncryptAddressDetails).new }

  def insert_address(street:, latitude:, longitude:, street2: nil, street3: nil)
    ActiveRecord::Base.connection.execute(<<~SQL)
      INSERT INTO addresses (street, street2, street3, city, region_code, postal_code, country, latitude, longitude, normalized_key, place_types, created_at, updated_at)
      VALUES (#{ActiveRecord::Base.connection.quote(street)},
              #{ActiveRecord::Base.connection.quote(street2)},
              #{ActiveRecord::Base.connection.quote(street3)},
              'Baltimore', 'MD', '21201', 'US',
              #{ActiveRecord::Base.connection.quote(latitude)},
              #{ActiveRecord::Base.connection.quote(longitude)},
              'balt-test-key', '[]', CURRENT_TIMESTAMP, CURRENT_TIMESTAMP)
    SQL
    id = Integer(ActiveRecord::Base.connection.select_value("SELECT last_insert_rowid()"))
    Address.find(id)
  end

  def raw_address(id)
    ActiveRecord::Base.connection.select_one(
      "SELECT street, street2, street3, latitude, longitude FROM addresses WHERE id = #{id}"
    ).to_h
  end

  def run_migration
    ActiveRecord::Migration.suppress_messages { migration.up }
  end

  # @lat: [[personal-detail-encryption#What is encrypted on an address]]
  it "encrypts plaintext address columns while preserving decrypted model values" do
    address = insert_address(
      street: "100 N Holliday St",
      street2: "Suite 400",
      latitude: "39.2904",
      longitude: "-76.6122"
    )

    run_migration

    raw = raw_address(address.id)
    expect(raw["street"]).to start_with('{"p":')
    expect(raw["street2"]).to start_with('{"p":')
    expect(raw["street3"]).to be_nil
    expect(raw["latitude"]).to start_with('{"p":')
    expect(raw["longitude"]).to start_with('{"p":')

    reloaded = Address.find(address.id)
    expect(reloaded.street).to eq("100 N Holliday St")
    expect(reloaded.street2).to eq("Suite 400")
    expect(reloaded.street3).to be_nil
    expect(reloaded.latitude).to eq("39.2904")
    expect(reloaded.longitude).to eq("-76.6122")
  end

  it "leaves an already-encrypted row byte-for-byte identical" do
    address = create(:address, street: "100 N Holliday St", street2: "Suite 400")
    before_raw = raw_address(address.id)

    expect(before_raw["street"]).to start_with('{"p":')
    expect(before_raw["street2"]).to start_with('{"p":')
    expect(before_raw["latitude"]).to start_with('{"p":')
    expect(before_raw["longitude"]).to start_with('{"p":')

    run_migration

    after_raw = raw_address(address.id)
    expect(after_raw).to eq(before_raw)
  end

  it "is idempotent and does not change rows on a second run" do
    address = insert_address(
      street: "100 N Holliday St",
      latitude: "39.2904",
      longitude: "-76.6122"
    )

    run_migration
    first_raw = raw_address(address.id)

    run_migration
    second_raw = raw_address(address.id)

    expect(second_raw).to eq(first_raw)
  end

  it "raises ActiveRecord::IrreversibleMigration on down" do
    expect { migration.down }.to raise_error(ActiveRecord::IrreversibleMigration)
  end
end
