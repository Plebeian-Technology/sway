# frozen_string_literal: true

# == Schema Information
#
# Table name: bill_section_references
# Database name: primary
#
#  id            :integer          not null, primary key
#  anchor        :text
#  article       :string           not null
#  authoritative :boolean          default(FALSE), not null
#  fuzzy_score   :integer
#  key           :string           not null
#  ordinal       :integer          not null
#  resolution    :integer          default("unresolved"), not null
#  section       :string           not null
#  title         :string
#  created_at    :datetime         not null
#  updated_at    :datetime         not null
#  bill_id       :integer          not null
#
# Indexes
#
#  idx_bill_section_refs_on_bill_ordinal     (bill_id,ordinal)
#  idx_bill_section_refs_on_key              (key)
#  index_bill_section_references_on_bill_id  (bill_id)
#
# Foreign Keys
#
#  bill_id  (bill_id => bills.id)
#
require "rails_helper"

RSpec.describe BillSectionReference, type: :model do
  describe "validations" do
    it "is valid with all required attributes" do
      expect(build(:bill_section_reference)).to be_valid
    end

    it "requires key" do
      record = build(:bill_section_reference, key: nil)
      expect(record).not_to be_valid
      expect(record.errors[:key]).to be_present
    end

    it "requires article" do
      record = build(:bill_section_reference, article: nil)
      expect(record).not_to be_valid
      expect(record.errors[:article]).to be_present
    end

    it "requires section" do
      record = build(:bill_section_reference, section: nil)
      expect(record).not_to be_valid
      expect(record.errors[:section]).to be_present
    end

    it "requires ordinal >= 0" do
      record = build(:bill_section_reference, ordinal: -1)
      expect(record).not_to be_valid
      expect(record.errors[:ordinal]).to be_present
    end
  end

  describe "enum :resolution" do
    it "exposes predicate methods" do
      record = build(:bill_section_reference, resolution: :exact)
      expect(record.exact?).to be(true)
      expect(record.fuzzy?).to be(false)
      expect(record.unresolved?).to be(false)
    end

    it "maps integer codes" do
      expect(BillSectionReference.resolutions).to eq("exact" => 0, "fuzzy" => 1, "unresolved" => 2)
    end
  end

  describe "associations" do
    it "destroys dependent bill_amendment_operations on destroy" do
      ref = create(:bill_section_reference)
      create(:bill_amendment_operation, bill: ref.bill, bill_section_reference: ref)
      expect { ref.destroy! }.to change(BillAmendmentOperation, :count).by(-1)
    end
  end

  describe "authoritative column" do
    it "defaults authoritative to false" do
      ref = build(:bill_section_reference)
      expect(ref.authoritative).to be(false)
      expect(ref.authoritative?).to be(false)
    end

    it "persists authoritative: true" do
      ref = create(:bill_section_reference, authoritative: true)
      expect(ref.reload.authoritative).to be(true)
      expect(ref.authoritative?).to be(true)
    end

    it "filters via .authoritative scope" do
      bill = create(:bill)
      ref_auth = create(:bill_section_reference, bill: bill, authoritative: true, ordinal: 0)
      create(:bill_section_reference, bill: bill, authoritative: false, ordinal: 1)

      expect(bill.bill_section_references.authoritative).to contain_exactly(ref_auth)
    end
  end
end
