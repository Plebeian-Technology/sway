# frozen_string_literal: true

require "rails_helper"

# @lat: [[personal-detail-encryption#Converting the rows that already exist]]
RSpec.describe "Production snapshot user encryption", :production_snapshot, type: :model do
  include_context "production snapshot (migrated)"

  # @lat: [[personal-detail-encryption#What is encrypted on a user]]
  it "leaves no user holding plaintext in sensitive personal detail columns" do
    expect(User.count).to be > 0

    sensitive_columns = %w[full_name email phone current_sign_in_ip last_sign_in_ip]
    rows = ActiveRecord::Base.connection.select_all(
      "SELECT id, full_name, email, phone, current_sign_in_ip, last_sign_in_ip FROM users"
    )

    rows.each do |row|
      sensitive_columns.each do |column|
        value = row[column]
        next if value.nil?

        expect(value).to start_with('{"p":')
      end
    end
  end

  it "decrypts all users cleanly via User model" do
    expect(User.count).to be > 0

    User.find_each do |user|
      expect(user.phone).to be_present
    end
  end

  # @lat: [[personal-detail-encryption#Why the phone number takes the weaker mode]]
  it "supports deterministic lookup by phone on migrated users" do
    expect(User.count).to be > 0

    User.find_each do |user|
      expect(User.find_by(phone: user.phone)).to eq(user)
    end
  end
end
