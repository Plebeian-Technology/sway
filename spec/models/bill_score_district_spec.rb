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

  describe "#at_large?" do
    it "is true for the district whose name carries no number" do
      sway_locale = create(:sway_locale)
      at_large = create(:district, sway_locale:, name: "#{sway_locale.region_code}0")
      numbered = create(:district, sway_locale:, name: "#{sway_locale.region_code}4")

      expect(build(:bill_score_district, district: at_large).at_large?).to be(true)
      expect(build(:bill_score_district, district: numbered).at_large?).to be(false)
    end
  end

  # @lat: [[voter-privacy-threshold#Bill totals are sent as rounded percentages]]
  describe "#for_percent and #against_percent" do
    it "are nil below ten voters" do
      district_score = build(:bill_score_district, for: 5, against: 4)

      expect(district_score.for_percent).to be_nil
      expect(district_score.against_percent).to be_nil
    end

    it "are nil for a unanimous split, which is not publishable" do
      district_score = build(:bill_score_district, for: 10, against: 0)

      expect(district_score.comparison_suppressed?).to be(true)
      expect(district_score.publishable?).to be(false)
      expect(district_score.for_percent).to be_nil
      expect(district_score.against_percent).to be_nil
    end

    {
      [7, 3] => [70, 30],
      [13, 6] => [70, 30],
      [39, 1] => [95, 5]
    }.each do |(district_for, district_against), (for_percent, against_percent)|
      it "are #{for_percent} and #{against_percent} for #{district_for} For and #{district_against} Against" do
        district_score = build(:bill_score_district, for: district_for, against: district_against)

        expect([district_score.for_percent, district_score.against_percent]).to eq([for_percent, against_percent])
      end
    end

    it "round to tens under 20 voters and sum to 100" do
      district_score = build(:bill_score_district, for: 2, against: 14)

      expect(district_score.for_percent).to eq(10)
      expect(district_score.against_percent).to eq(90)
    end
  end
end
