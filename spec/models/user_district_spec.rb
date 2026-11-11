# == Schema Information
#
# Table name: user_districts
# Database name: primary
#
#  id          :integer          not null, primary key
#  active      :boolean          default(TRUE), not null
#  created_at  :datetime         not null
#  updated_at  :datetime         not null
#  district_id :integer          not null
#  user_id     :integer          not null
#
# Indexes
#
#  index_user_districts_on_user_id_and_district_id  (user_id,district_id) UNIQUE
#
# Foreign Keys
#
#  district_id  (district_id => districts.id)
#  user_id      (user_id => users.id)
#
require "rails_helper"

# A stored record of every district a user has ever been assigned to, so the history
# can be compared over time. Rows are never deleted. Moving a user to a different
# district flips the `active` flag instead of adding a second row, the same way
# UserLegislator works.
RSpec.describe UserDistrict, type: :model do
  describe "validations" do
    it "requires a user" do
      user_district = build(:user_district, user: nil)
      expect(user_district).not_to be_valid
    end

    it "requires a district" do
      user_district = build(:user_district, district: nil)
      expect(user_district).not_to be_valid
    end

    it "rejects a duplicate (user, district) pair" do
      user = create(:user)
      district = create(:district)
      create(:user_district, user:, district:)

      dup = build(:user_district, user:, district:)

      expect(dup).not_to be_valid
      expect(dup.errors[:district_id]).to be_present
    end
  end

  describe "defaults" do
    it "defaults active to true" do
      user_district = build(:user_district)
      expect(user_district.active).to be(true)
    end
  end

  describe ".active" do
    it "returns only active rows" do
      active_ud = create(:user_district, active: true)
      inactive_ud = create(:user_district, active: false)

      expect(UserDistrict.active).to include(active_ud)
      expect(UserDistrict.active).not_to include(inactive_ud)
    end
  end

  describe "reactivation convention" do
    it "find_or_initialize_by reuses an inactive row rather than creating a duplicate" do
      user = create(:user)
      district = create(:district)
      inactive = create(:user_district, user:, district:, active: false)

      reactivated = UserDistrict.find_or_initialize_by(user:, district:)
      reactivated.active = true
      reactivated.save!

      expect(reactivated.id).to eq(inactive.id)
      expect(UserDistrict.count).to eq(1)
      expect(reactivated.reload.active).to be(true)
    end
  end

  describe "User#user_districts" do
    it "resolves the association" do
      user = create(:user)
      user_district = create(:user_district, user:)

      expect(user.user_districts).to include(user_district)
    end
  end
end
