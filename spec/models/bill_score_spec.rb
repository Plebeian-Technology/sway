# == Schema Information
#
# Table name: bill_scores
# Database name: primary
#
#  id         :integer          not null, primary key
#  against    :integer          default(0), not null
#  for        :integer          default(0), not null
#  created_at :datetime         not null
#  updated_at :datetime         not null
#  bill_id    :integer          not null
#
# Indexes
#
#  index_bill_scores_on_bill_id  (bill_id) UNIQUE
#
# Foreign Keys
#
#  bill_id  (bill_id => bills.id)
#
require "rails_helper"

RSpec.describe BillScore, type: :model do
  describe "validations" do
    it "is valid with defaulted for/against counters" do
      bill_score = build(:bill_score)
      expect(bill_score).to be_valid
    end
  end

  describe "associations" do
    it "belongs to a bill" do
      expect(create(:bill_score).bill).to be_a(Bill)
    end

    it "delegates sway_locale to its bill" do
      bs = create(:bill_score)
      expect(bs.sway_locale).to eq(bs.bill.sway_locale)
    end
  end

  # The unique index on bill_id is what makes BillScore.find_or_create_by and
  # create_or_find_by! safe, so two people voting at once land on the same row
  # instead of splitting the tally. Bill#create_default_bill_score already makes
  # one BillScore for every bill as it is created.
  describe "bill_id uniqueness" do
    it "rejects a second BillScore for the same bill" do
      bill = create(:bill)
      expect(BillScore.where(bill_id: bill.id).count).to eq(1)

      expect {
        BillScore.create!(bill: bill)
      }.to raise_error(ActiveRecord::RecordNotUnique)
    end
  end

  # @lat: [[voter-privacy-threshold#Bill totals are sent as rounded percentages]]
  describe "#comparison_suppressed?, #for_percent and #against_percent" do
    def score_with(bill_for, bill_against)
      build(:bill_score, for: bill_for, against: bill_against)
    end

    {
      [7, 3] => [70, 30],
      [13, 6] => [70, 30],
      [39, 1] => [95, 5]
    }.each do |(bill_for, bill_against), (for_percent, against_percent)|
      it "send #{for_percent} and #{against_percent} for #{bill_for} For and #{bill_against} Against" do
        score = score_with(bill_for, bill_against)

        expect(score.comparison_suppressed?).to be(false)
        expect([score.for_percent, score.against_percent]).to eq([for_percent, against_percent])
        expect([score.visible_for, score.visible_against]).to eq([bill_for, bill_against])
      end
    end

    it "withhold a unanimous split of ten voters" do
      score = score_with(10, 0)

      expect(score.comparison_suppressed?).to be(true)
      expect([score.for_percent, score.against_percent, score.visible_for, score.visible_against]).to eq([nil, nil, nil, nil])
    end

    it "withhold a unanimous Against split" do
      score = score_with(0, 12)

      expect(score.comparison_suppressed?).to be(true)
      expect([score.for_percent, score.against_percent]).to eq([nil, nil])
    end

    it "withhold nine voters" do
      score = score_with(6, 3)

      expect(score.comparison_suppressed?).to be(true)
      expect([score.for_percent, score.against_percent, score.visible_for, score.visible_against]).to eq([nil, nil, nil, nil])
    end

    it "keep voters_needed at the number of voters under ten" do
      expect(score_with(6, 3).voters_needed).to eq(1)
      expect(score_with(10, 0).voters_needed).to eq(0)
    end

    it "send the percentages from both builders" do
      score = create(:bill_score, for: 7, against: 3)
      user = create(:user)

      expect(score.to_builder.attributes!).to include("for_percent" => 70, "against_percent" => 30)
      expect(score.to_builder_with_user(user).attributes!).to include("for_percent" => 70, "against_percent" => 30)
    end

    it "send nil percentages from both builders for a unanimous split" do
      score = create(:bill_score, for: 10, against: 0)
      user = create(:user)

      expect(score.to_builder.attributes!).to include("for_percent" => nil, "against_percent" => nil, "comparison_suppressed" => true)
      expect(score.to_builder_with_user(user).attributes!).to include("for_percent" => nil, "against_percent" => nil)
    end
  end

  # @lat: [[voter-privacy-threshold#Districts are sent as percentages only]]
  describe "#publishable_districts" do
    minimum = VoteComparisonPrivacy::MINIMUM_VOTERS

    let(:bill) { create(:bill) }
    let(:sway_locale) { bill.sway_locale }
    let(:score) { bill.bill_score }
    let(:district_four) { create(:district, sway_locale:, name: "#{sway_locale.region_code}4") }
    let(:district_seven) { create(:district, sway_locale:, name: "#{sway_locale.region_code}7") }
    let(:at_large) { create(:district, sway_locale:, name: "#{sway_locale.region_code}0") }

    def tally(bill_for:, bill_against:, rows:)
      score.update!(for: bill_for, against: bill_against)
      rows.each do |district, (district_for, district_against)|
        create(:bill_score_district, bill_score: score, district:, for: district_for, against: district_against)
      end
      score.reload
    end

    def published_names
      score.publishable_districts.map { |row| row.district.name }
    end

    it "publishes nothing when one voter sits outside the only district with ten voters" do
      tally(bill_for: 8, bill_against: 3, rows: {district_four => [7, 3], district_seven => [1, 0], at_large => [8, 3]})

      expect(score.comparison_suppressed?).to be(false)
      expect(published_names).to eq([])
    end

    it "publishes the districts when every voter sits inside them" do
      tally(bill_for: 7, bill_against: 3, rows: {district_four => [7, 3], at_large => [7, 3]})

      expect(published_names).to eq([district_four.name])
    end

    it "publishes the districts when exactly the minimum of voters sits outside them" do
      tally(bill_for: 7 + minimum, bill_against: 3, rows: {district_four => [7, 3], at_large => [7 + minimum, 3]})

      expect(published_names).to eq([district_four.name])
    end

    it "publishes nothing when one voter short of the minimum sits outside the districts" do
      tally(bill_for: 7 + minimum - 1, bill_against: 3, rows: {district_four => [7, 3], at_large => [7 + minimum - 1, 3]})

      expect(published_names).to eq([])
    end

    it "publishes nothing when the districts hold more voters than the bill" do
      tally(bill_for: 12, bill_against: 3, rows: {district_four => [7, 3], district_seven => [7, 3]})

      expect(published_names).to eq([])
    end

    it "leaves out a unanimous district with ten voters" do
      tally(bill_for: 20, bill_against: 3, rows: {district_four => [7, 3], district_seven => [10, 0], at_large => [20, 3]})

      expect(published_names).to eq([district_four.name])
    end
  end

  # @lat: [[voter-privacy-threshold#Legislator scores count only bills that reached the minimum]]
  describe "#countable_district_ids" do
    minimum = VoteComparisonPrivacy::MINIMUM_VOTERS

    let(:bill) { create(:bill) }
    let(:sway_locale) { bill.sway_locale }
    let(:score) { bill.bill_score }
    let(:district_four) { create(:district, sway_locale:, name: "#{sway_locale.region_code}4") }
    let(:district_seven) { create(:district, sway_locale:, name: "#{sway_locale.region_code}7") }
    let(:at_large) { create(:district, sway_locale:, name: "MD0") }
    let(:other_at_large) { create(:district, sway_locale:, name: "VA0") }

    def tally(bill_for:, bill_against:, rows:)
      score.update!(for: bill_for, against: bill_against)
      rows.each do |district, (district_for, district_against)|
        create(:bill_score_district, bill_score: score, district:, for: district_for, against: district_against)
      end
      score.reload
    end

    it "counts nothing for a district with ten voters while one voter sits outside the shown districts" do
      tally(bill_for: 8, bill_against: 3, rows: {district_four => [7, 3], district_seven => [1, 0]})

      expect(score.countable_district_ids).to eq([])
    end

    it "counts the shown districts when the voters outside them number zero or the minimum" do
      tally(bill_for: 7 + minimum, bill_against: 3, rows: {district_four => [7, 3], district_seven => [minimum - 1, 0]})

      expect(score.countable_district_ids).to eq([district_four.id])
    end

    it "counts an at-large tally only when the voters outside it number zero or the minimum" do
      tally(bill_for: 12, bill_against: 1, rows: {at_large => [10, 1], other_at_large => [2, 0]})
      expect(score.countable_district_ids).to eq([])

      score.bill_score_districts.find_by!(district: other_at_large).update!(for: minimum, against: 1)
      score.update!(for: 10 + minimum, against: 2)
      expect(score.reload.countable_district_ids).to contain_exactly(at_large.id, other_at_large.id)
    end

    it "counts an at-large tally that holds every voter of the bill" do
      tally(bill_for: 7, bill_against: 3, rows: {at_large => [7, 3]})

      expect(score.countable_district_ids).to eq([at_large.id])
    end

    it "never counts a unanimous district tally" do
      tally(bill_for: 20, bill_against: 3, rows: {district_four => [7, 3], district_seven => [10, 0]})

      expect(score.countable_district_ids).to eq([district_four.id])
    end

    it "never counts an at-large tally under the minimum" do
      tally(bill_for: 7, bill_against: 2, rows: {at_large => [7, 2]})

      expect(score.countable_district_ids).to eq([])
    end
  end
end
