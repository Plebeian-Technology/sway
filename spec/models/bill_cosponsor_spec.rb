# == Schema Information
#
# Table name: bill_cosponsors
# Database name: primary
#
#  id            :integer          not null, primary key
#  created_at    :datetime         not null
#  updated_at    :datetime         not null
#  bill_id       :integer          not null
#  legislator_id :integer          not null
#
# Indexes
#
#  index_bill_cosponsors_on_bill_id        (bill_id)
#  index_bill_cosponsors_on_legislator_id  (legislator_id)
#
# Foreign Keys
#
#  bill_id        (bill_id => bills.id)
#  legislator_id  (legislator_id => legislators.id)
#
require "rails_helper"

RSpec.describe BillCosponsor, type: :model do
  describe "associations" do
    it "persists with a bill and legislator via factory" do
      record = create(:bill_cosponsor)
      expect(record).to be_persisted
      expect(record.bill).to be_a(Bill)
      expect(record.legislator).to be_a(Legislator)
    end
  end

  describe "validations" do
    it "is valid with factory attributes" do
      expect(build(:bill_cosponsor)).to be_valid
    end

    it "requires both bill and legislator" do
      record = BillCosponsor.new
      expect(record).not_to be_valid
      expect(record.errors[:bill]).to be_present
      expect(record.errors[:legislator]).to be_present
    end
  end
end
