# == Schema Information
#
# Table name: user_addresses
# Database name: primary
#
#  id         :integer          not null, primary key
#  created_at :datetime         not null
#  updated_at :datetime         not null
#  address_id :integer          not null
#  user_id    :integer          not null
#
# Indexes
#
#  index_user_addresses_on_address_id  (address_id)
#  index_user_addresses_on_user_id     (user_id) UNIQUE
#
# Foreign Keys
#
#  address_id  (address_id => addresses.id)
#  user_id     (user_id => users.id)
#
require "rails_helper"

RSpec.describe UserAddress, type: :model do
  describe "associations" do
    it "belongs to a user" do
      record = create(:user_address)
      expect(record.user).to be_a(User)
    end

    it "belongs to an address" do
      record = create(:user_address)
      expect(record.address).to be_a(Address)
    end
  end

  describe "validations" do
    it "requires an address (belongs_to is required by default)" do
      record = build(:user_address, address: nil)
      expect(record).not_to be_valid
    end

    it "requires a user (belongs_to is required by default)" do
      record = build(:user_address, user: nil)
      expect(record).not_to be_valid
    end

    # @lat: [[identity-and-access#A user holds one address]]
    it "rejects a second row for a user that already has one" do
      existing = create(:user_address)
      record = build(:user_address, user: existing.user, address: create(:address))

      expect(record).not_to be_valid
      expect(record.errors[:user_id]).to be_present
    end
  end
end
