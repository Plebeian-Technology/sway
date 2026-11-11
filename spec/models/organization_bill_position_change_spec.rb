# frozen_string_literal: true

# == Schema Information
#
# Table name: organization_bill_position_changes
# Database name: primary
#
#  id                            :integer          not null, primary key
#  new_summary                   :text             not null
#  new_support                   :string           not null
#  previous_summary              :text             not null
#  previous_support              :string           not null
#  rejected_at                   :datetime
#  status                        :integer          not null
#  created_at                    :datetime         not null
#  updated_at                    :datetime         not null
#  approved_by_id                :integer
#  organization_bill_position_id :integer          not null
#  rejected_by_id                :integer
#  updated_by_id                 :integer          not null
#
# Indexes
#
#  idx_on_organization_bill_position_id_789f74d3d4             (organization_bill_position_id)
#  index_organization_bill_position_changes_on_approved_by_id  (approved_by_id)
#  index_organization_bill_position_changes_on_rejected_by_id  (rejected_by_id)
#  index_organization_bill_position_changes_on_updated_by_id   (updated_by_id)
#
# Foreign Keys
#
#  approved_by_id                 (approved_by_id => users.id)
#  organization_bill_position_id  (organization_bill_position_id => organization_bill_positions.id)
#  rejected_by_id                 (rejected_by_id => users.id)
#  updated_by_id                  (updated_by_id => users.id)
#
require "rails_helper"

RSpec.describe OrganizationBillPositionChange, type: :model do
  describe "associations" do
    it "belongs to an organization_bill_position" do
      record = create(:organization_bill_position_change)
      expect(record.organization_bill_position).to be_a(OrganizationBillPosition)
    end

    it "belongs to updated_by (User)" do
      record = create(:organization_bill_position_change)
      expect(record.updated_by).to be_a(User)
    end

    it "allows approved_by to be nil (optional)" do
      record = create(:organization_bill_position_change, approved_by_id: nil)
      expect(record.approved_by).to be_nil
      expect(record).to be_valid
    end
  end

  describe "validations" do
    it "is valid with a factory-built instance" do
      expect(create(:organization_bill_position_change)).to be_valid
    end

    it "requires new_summary" do
      record = build(:organization_bill_position_change, new_summary: nil)
      expect(record.valid?).to be(false)
      expect(record.errors[:new_summary]).to be_present
    end

    # @lat: [[organization-position-removal#A refusal reaches the operator as a message, not a 500]]
    it "requires new_support — a blank value used to reach the approving admin as a 500" do
      record = build(:organization_bill_position_change, new_support: "")
      expect(record.valid?).to be(false)
      expect(record.errors[:new_support]).to be_present
    end

    it "rejects a new_support value outside the recognized stances" do
      record = build(:organization_bill_position_change, new_support: "maybe")
      expect(record.valid?).to be(false)
      expect(record.errors[:new_support]).to be_present
    end

    it "accepts every stance OrganizationBillPosition itself recognizes" do
      OrganizationBillPosition::STANCE_TO_SUPPORT.each_key do |stance|
        record = build(:organization_bill_position_change, new_support: stance)
        expect(record.valid?).to be(true)
      end
    end
  end

  describe "enum status" do
    it "defaults to pending" do
      record = create(:organization_bill_position_change)
      expect(record.status).to eq("pending")
    end

    it "supports approved and rejected" do
      record = create(:organization_bill_position_change)
      # The validators check both directions: the matching *_by_id column
      # must be stamped alongside the status change, and the opposite
      # *_by_id / rejected_at must be cleared. Calling the enum bang method
      # by itself, with nothing else set, leaves an invalid row.
      record.update!(approved_by: create(:user), status: :approved)
      expect(record.status).to eq("approved")
      record.update!(approved_by: nil, rejected_by: create(:user), rejected_at: Time.current, status: :rejected)
      expect(record.status).to eq("rejected")
    end
  end

  describe "#approved?" do
    it "is false when approved_by_id is nil" do
      record =
        create(:organization_bill_position_change, approved_by_id: nil)
      expect(record.approved?).to be(false)
    end

    it "is true when approved_by_id is set" do
      approver = create(:user)
      # The validators check both directions: status: :approved must be set
      # alongside approved_by. The old inconsistent state — approved_by set
      # but status still pending — is now rejected at save time.
      record =
        create(:organization_bill_position_change, approved_by: approver, status: :approved)
      expect(record.approved?).to be(true)
    end
  end

  # @lat: [[organization-bill-position-change-design#Why STANCE_TO_SUPPORT lives on OrganizationBillPosition]]
  describe "#finalized?" do
    it "is false when the row is pending" do
      record = create(:organization_bill_position_change)
      expect(record.finalized?).to be(false)
    end

    it "is true when the row is approved" do
      # The validators check both directions: status: :approved must be set
      # alongside approved_by.
      record = create(:organization_bill_position_change, approved_by: create(:user), status: :approved)
      expect(record.finalized?).to be(true)
    end

    it "is true when the row is rejected" do
      record = create(:organization_bill_position_change)
      record.update!(rejected_by: create(:user), rejected_at: Time.current, status: :rejected)
      expect(record.finalized?).to be(true)
    end
  end
end
