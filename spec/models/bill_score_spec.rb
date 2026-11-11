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
end
