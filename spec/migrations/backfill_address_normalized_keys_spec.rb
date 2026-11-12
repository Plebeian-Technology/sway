# frozen_string_literal: true

require "rails_helper"
require Rails.root.join("db", "data", "20261111000001_backfill_address_normalized_keys")

# @lat: [[address-normalized-key#Why the backfill reports collisions instead of merging]]
RSpec.describe "BackfillAddressNormalizedKeys data migration", type: :model do
  let(:migration) { Object.const_get(:BackfillAddressNormalizedKeys).new }

  def insert_address(street:, latitude:, longitude:, street2: nil, street3: nil)
    ActiveRecord::Base.connection.execute(<<~SQL)
      INSERT INTO addresses (street, street2, street3, city, region_code, postal_code, country, latitude, longitude, normalized_key, place_types, created_at, updated_at)
      VALUES (#{ActiveRecord::Base.connection.quote(street)},
              #{ActiveRecord::Base.connection.quote(street2)},
              #{ActiveRecord::Base.connection.quote(street3)},
              'Baltimore', 'MD', '21201', 'US',
              #{ActiveRecord::Base.connection.quote(latitude)},
              #{ActiveRecord::Base.connection.quote(longitude)},
              NULL, '[]', CURRENT_TIMESTAMP, CURRENT_TIMESTAMP)
    SQL
    id = ActiveRecord::Base.connection.select_value("SELECT last_insert_rowid()")
    Address.find(id)
  end

  def run_migration
    ActiveRecord::Migration.suppress_messages { migration.up }
  end

  it "fills normalized_key for geocoded rows using Address.normalized_key_for" do
    first = insert_address(street: "100 Main St", latitude: "39.2904", longitude: "-76.6122")
    second = insert_address(street: "200 Main St", latitude: "39.2915", longitude: "-76.6133", street2: "Apt 4B")
    third = insert_address(street: "300 Main St", latitude: nil, longitude: nil)

    run_migration

    expect(first.reload.normalized_key).to eq(Address.normalized_key_for(latitude: "39.2904", longitude: "-76.6122"))
    expect(second.reload.normalized_key).to eq(Address.normalized_key_for(latitude: "39.2915", longitude: "-76.6133", street2: "Apt 4B"))
    expect(third.reload.normalized_key).to be_nil
  end

  it "is idempotent and does not change keys on a second run" do
    address = insert_address(street: "100 Main St", latitude: "39.2904", longitude: "-76.6122")

    run_migration
    first_key = address.reload.normalized_key
    expect(first_key).not_to be_nil

    expect { run_migration }.not_to change { address.reload.normalized_key }
  end

  it "reports key collisions without altering rows" do
    first = insert_address(street: "100 Main St", latitude: "39.2904", longitude: "-76.6122")
    second = insert_address(street: "102 Main St", latitude: "39.2904", longitude: "-76.6122")

    expect { migration.up }
      .to output(/shared by more than one row.*#{first.id}.*#{second.id}|shared by more than one row.*#{second.id}.*#{first.id}/m)
      .to_stdout

    expect(first.reload.normalized_key).to eq(second.reload.normalized_key)
  end

  it "raises ActiveRecord::IrreversibleMigration on down" do
    expect { migration.down }.to raise_error(ActiveRecord::IrreversibleMigration)
  end
end
