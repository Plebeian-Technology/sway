# == Schema Information
#
# Table name: districts
# Database name: primary
#
#  id             :integer          not null, primary key
#  name           :string           not null
#  created_at     :datetime         not null
#  updated_at     :datetime         not null
#  sway_locale_id :integer          not null
#
# Indexes
#
#  index_districts_on_name_and_sway_locale_id  (name,sway_locale_id) UNIQUE
#  index_districts_on_sway_locale_id           (sway_locale_id)
#
# Foreign Keys
#
#  sway_locale_id  (sway_locale_id => sway_locales.id)
#
require "rails_helper"

RSpec.describe District, type: :model do
  describe "validations" do
    it "is valid with a name and a sway_locale" do
      expect(build(:district)).to be_valid
    end
  end

  describe "associations" do
    it "belongs to a sway_locale" do
      expect(create(:district).sway_locale).to be_a(SwayLocale)
    end

    it "has many legislator_terms" do
      district = create(:district)
      expect(district.legislator_terms).to respond_to(:each)
    end
  end

  describe "#number" do
    it "extracts the numeric portion of the district name" do
      district = build(:district, name: "MD7")
      expect(district.number).to eq(7)
    end
  end

  describe "#region_code" do
    it "extracts the alpha portion of the district name" do
      district = build(:district, name: "MD7")
      expect(district.region_code).to eq("MD")
    end
  end
end
