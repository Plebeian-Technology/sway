# == Schema Information
#
# Table name: bill_score_districts
# Database name: primary
#
#  id            :integer          not null, primary key
#  against       :integer          default(0), not null
#  for           :integer          default(0), not null
#  created_at    :datetime         not null
#  updated_at    :datetime         not null
#  bill_score_id :integer          not null
#  district_id   :integer          not null
#
# Indexes
#
#  index_bill_score_districts_on_bs_and_district  (bill_score_id,district_id) UNIQUE
#  index_bill_score_districts_on_district_id      (district_id)
#
# Foreign Keys
#
#  bill_score_id  (bill_score_id => bill_scores.id)
#  district_id    (district_id => districts.id)
#
require "rails_helper"

RSpec.describe BillScoreDistrict, type: :model do
  describe "validations" do
    it "defaults for/against counters to 0" do
      bsd = build(:bill_score_district)
      expect(bsd.for).to eq(0)
      expect(bsd.against).to eq(0)
    end
  end

  describe "associations" do
    it "belongs to a bill_score" do
      expect(create(:bill_score_district).bill_score).to be_a(BillScore)
    end

    it "belongs to a district" do
      expect(create(:bill_score_district).district).to be_a(District)
    end
  end

  # The unique index across (bill_score_id, district_id) is what makes
  # find_or_create_by! safe in ScoreRecomputeService and ScoreUpdaterService, so
  # a district's tally can never end up split across two rows.
  describe "(bill_score_id, district_id) uniqueness" do
    it "rejects a duplicate district row for one bill_score" do
      existing = create(:bill_score_district)

      expect {
        BillScoreDistrict.create!(
          bill_score: existing.bill_score,
          district: existing.district
        )
      }.to raise_error(ActiveRecord::RecordNotUnique)
    end
  end
end
