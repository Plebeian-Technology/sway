# frozen_string_literal: true

require "rails_helper"
require Rails.root.join("db", "data", "20261111000003_encrypt_user_personal_details")

# @lat: [[personal-detail-encryption#Converting the rows that already exist]]
RSpec.describe "EncryptUserPersonalDetails data migration", type: :model do
  let(:migration) { Object.const_get(:EncryptUserPersonalDetails).new }

  def insert_user(full_name:, email:, phone:, current_sign_in_ip: nil, last_sign_in_ip: nil)
    ActiveRecord::Base.connection.execute(<<~SQL)
      INSERT INTO users (full_name, email, phone, current_sign_in_ip, last_sign_in_ip, webauthn_id, created_at, updated_at)
      VALUES (#{ActiveRecord::Base.connection.quote(full_name)},
              #{ActiveRecord::Base.connection.quote(email)},
              #{ActiveRecord::Base.connection.quote(phone)},
              #{ActiveRecord::Base.connection.quote(current_sign_in_ip)},
              #{ActiveRecord::Base.connection.quote(last_sign_in_ip)},
              #{ActiveRecord::Base.connection.quote(SecureRandom.uuid)},
              CURRENT_TIMESTAMP, CURRENT_TIMESTAMP)
    SQL
    id = Integer(ActiveRecord::Base.connection.select_value("SELECT last_insert_rowid()"))
    User.find(id)
  end

  def raw_user(id)
    ActiveRecord::Base.connection.select_one(
      "SELECT full_name, email, phone, current_sign_in_ip, last_sign_in_ip FROM users WHERE id = #{id}"
    ).to_h
  end

  def run_migration
    ActiveRecord::Migration.suppress_messages { migration.up }
  end

  # @lat: [[personal-detail-encryption#What is encrypted on a user]]
  it "encrypts plaintext user columns while preserving decrypted model values and lookups" do
    user = insert_user(
      full_name: "Ada Lovelace",
      email: "ada@example.com",
      phone: "4105550100",
      current_sign_in_ip: "192.0.2.1",
      last_sign_in_ip: "192.0.2.2"
    )

    run_migration

    raw = raw_user(user.id)
    expect(raw["full_name"]).to start_with('{"p":')
    expect(raw["email"]).to start_with('{"p":')
    expect(raw["phone"]).to start_with('{"p":')
    expect(raw["current_sign_in_ip"]).to start_with('{"p":')
    expect(raw["last_sign_in_ip"]).to start_with('{"p":')

    reloaded = User.find(user.id)
    expect(reloaded.full_name).to eq("Ada Lovelace")
    expect(reloaded.email).to eq("ada@example.com")
    expect(reloaded.phone).to eq("4105550100")
    expect(reloaded.current_sign_in_ip).to eq("192.0.2.1")
    expect(reloaded.last_sign_in_ip).to eq("192.0.2.2")

    # @lat: [[personal-detail-encryption#Why the phone number takes the weaker mode]]
    expect(User.find_by(phone: "4105550100")).to eq(reloaded)
    expect(User.find_by(email: "ada@example.com")).to eq(reloaded)
  end

  it "leaves an already-encrypted row byte-for-byte identical" do
    user = create(
      :user,
      full_name: "Ada Lovelace",
      email: "ada@example.com",
      phone: "4105550100",
      current_sign_in_ip: "192.0.2.1",
      last_sign_in_ip: "192.0.2.2"
    )
    before_raw = raw_user(user.id)

    expect(before_raw["full_name"]).to start_with('{"p":')
    expect(before_raw["email"]).to start_with('{"p":')
    expect(before_raw["phone"]).to start_with('{"p":')
    expect(before_raw["current_sign_in_ip"]).to start_with('{"p":')
    expect(before_raw["last_sign_in_ip"]).to start_with('{"p":')

    run_migration

    after_raw = raw_user(user.id)
    expect(after_raw).to eq(before_raw)
  end

  it "is idempotent and does not change rows on a second run" do
    user = insert_user(
      full_name: "Ada Lovelace",
      email: "ada@example.com",
      phone: "4105550100",
      current_sign_in_ip: "192.0.2.1",
      last_sign_in_ip: "192.0.2.2"
    )

    run_migration
    first_raw = raw_user(user.id)

    run_migration
    second_raw = raw_user(user.id)

    expect(second_raw).to eq(first_raw)
  end

  it "raises ActiveRecord::IrreversibleMigration on down" do
    expect { migration.down }.to raise_error(ActiveRecord::IrreversibleMigration)
  end
end
