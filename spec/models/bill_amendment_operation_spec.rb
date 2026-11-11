# frozen_string_literal: true

# == Schema Information
#
# Table name: bill_amendment_operations
# Database name: primary
#
#  id                        :integer          not null, primary key
#  anchor_text               :text
#  char_end                  :integer          default(-1), not null
#  char_start                :integer          default(-1), not null
#  operation                 :integer          not null
#  ordinal                   :integer          not null
#  replacement_text          :text
#  source                    :integer          default("text_pattern"), not null
#  created_at                :datetime         not null
#  updated_at                :datetime         not null
#  bill_id                   :integer          not null
#  bill_section_reference_id :integer
#  target_law_section_id     :integer
#
# Indexes
#
#  idx_bill_amendment_ops_on_bill_ordinal                        (bill_id,ordinal)
#  index_bill_amendment_operations_on_bill_id                    (bill_id)
#  index_bill_amendment_operations_on_bill_section_reference_id  (bill_section_reference_id)
#  index_bill_amendment_operations_on_target_law_section_id      (target_law_section_id)
#
# Foreign Keys
#
#  bill_id                    (bill_id => bills.id)
#  bill_section_reference_id  (bill_section_reference_id => bill_section_references.id)
#  target_law_section_id      (target_law_section_id => law_sections.id)
#
require "rails_helper"

RSpec.describe BillAmendmentOperation, type: :model do
  describe "enum :operation" do
    it "exposes predicate methods" do
      record = build(:bill_amendment_operation, operation: :strike)
      expect(record.strike?).to be(true)
      expect(record.insert?).to be(false)
      expect(record.replace?).to be(false)
    end

    it "maps integer codes" do
      expect(BillAmendmentOperation.operations).to eq("strike" => 0, "insert" => 1, "replace" => 2)
    end
  end

  describe "enum :source" do
    it "defaults to :text_pattern" do
      expect(BillAmendmentOperation.new.source).to eq("text_pattern")
    end

    it "exposes predicate methods" do
      record = build(:bill_amendment_operation, source: :markup)
      expect(record.markup?).to be(true)
      expect(record.text_pattern?).to be(false)
    end

    it "maps integer codes" do
      expect(BillAmendmentOperation.sources).to eq("text_pattern" => 0, "markup" => 1)
    end
  end

  describe "associations" do
    it "belongs to bill" do
      expect(BillAmendmentOperation.reflect_on_association(:bill).macro).to eq(:belongs_to)
    end

    it "belongs to bill_section_reference (optional)" do
      assoc = BillAmendmentOperation.reflect_on_association(:bill_section_reference)
      expect(assoc.macro).to eq(:belongs_to)
      expect(assoc.options[:optional]).to be(true)
    end

    it "belongs to target_law_section (optional) -> LawSection" do
      assoc = BillAmendmentOperation.reflect_on_association(:target_law_section)
      expect(assoc.macro).to eq(:belongs_to)
      expect(assoc.options[:optional]).to be(true)
      expect(assoc.options[:class_name]).to eq("LawSection")
    end
  end

  describe "validations" do
    it "requires ordinal >= 0" do
      record = build(:bill_amendment_operation, ordinal: -1)
      expect(record).not_to be_valid
      expect(record.errors[:ordinal]).to be_present
    end
  end

  describe "default scope" do
    it "orders by ordinal ascending" do
      bill = create(:bill)
      _op2 = create(:bill_amendment_operation, bill: bill, ordinal: 2)
      _op0 = create(:bill_amendment_operation, bill: bill, ordinal: 0)
      _op1 = create(:bill_amendment_operation, bill: bill, ordinal: 1)
      expect(bill.bill_amendment_operations.pluck(:ordinal)).to eq([0, 1, 2])
    end
  end
end
