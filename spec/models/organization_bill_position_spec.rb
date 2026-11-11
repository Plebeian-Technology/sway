# frozen_string_literal: true

# == Schema Information
#
# Table name: organization_bill_positions
# Database name: primary
#
#  id              :integer          not null, primary key
#  active          :boolean          default(FALSE), not null
#  ai_summary      :text
#  summary         :text             not null
#  support         :string           not null
#  created_at      :datetime         not null
#  updated_at      :datetime         not null
#  bill_id         :integer          not null
#  organization_id :integer          not null
#
# Indexes
#
#  idx_on_bill_id_organization_id_f380340a40             (bill_id,organization_id) UNIQUE
#  index_organization_bill_positions_on_active           (active)
#  index_organization_bill_positions_on_bill_id          (bill_id)
#  index_organization_bill_positions_on_organization_id  (organization_id)
#
# Foreign Keys
#
#  bill_id          (bill_id => bills.id)
#  organization_id  (organization_id => organizations.id)
#
require "rails_helper"

RSpec.describe OrganizationBillPosition, type: :model do
  describe "associations" do
    it "belongs to an organization" do
      record = create(:organization_bill_position)
      expect(record.organization).to be_a(Organization)
    end

    it "belongs to a bill" do
      record = create(:organization_bill_position)
      expect(record.bill).to be_a(Bill)
    end

    it "has many position_changes (destroyed with parent)" do
      record = create(:organization_bill_position)
      change =
        create(:organization_bill_position_change, organization_bill_position: record)
      expect(record.position_changes).to include(change)
    end
  end

  describe "validations" do
    it "is valid with a factory-built instance" do
      expect(create(:organization_bill_position)).to be_valid
    end

    it "requires support" do
      record = build(:organization_bill_position, support: nil)
      expect(record.valid?).to be(false)
      expect(record.errors[:support]).to be_present
    end

    it "requires summary" do
      record = build(:organization_bill_position, summary: nil)
      expect(record.valid?).to be(false)
      expect(record.errors[:summary]).to be_present
    end

    it "enforces bill_id unique per organization" do
      first = create(:organization_bill_position)
      dup =
        build(
          :organization_bill_position,
          bill: first.bill,
          organization: first.organization
        )
      expect(dup.valid?).to be(false)
      expect(dup.errors[:bill_id]).to be_present
    end
  end

  # @lat: [[organization-bill-position-change-design#Why STANCE_TO_SUPPORT lives on OrganizationBillPosition]]
  describe ".normalize_support" do
    it "maps 'support' to 'FOR'" do
      expect(described_class.normalize_support("support")).to eq("FOR")
    end

    it "maps 'oppose' to 'AGAINST'" do
      expect(described_class.normalize_support("oppose")).to eq("AGAINST")
    end

    it "maps 'neutral' to 'ABSTAIN'" do
      expect(described_class.normalize_support("neutral")).to eq("ABSTAIN")
    end

    it "passes legacy 'FOR'/'AGAINST'/'ABSTAIN' values through unchanged" do
      %w[FOR AGAINST ABSTAIN].each do |v|
        expect(described_class.normalize_support(v)).to eq(v)
      end
    end

    it "returns nil for unrecognised inputs" do
      expect(described_class.normalize_support("garbage")).to be_nil
      expect(described_class.normalize_support(nil)).to be_nil
      expect(described_class.normalize_support("")).to be_nil
    end
  end

  describe "#latest_position_change" do
    it "returns the most recent position change" do
      position = create(:organization_bill_position)
      _old =
        create(
          :organization_bill_position_change,
          organization_bill_position: position,
          created_at: 2.days.ago
        )
      newer =
        create(
          :organization_bill_position_change,
          organization_bill_position: position,
          created_at: 1.hour.ago
        )
      expect(position.latest_position_change).to eq(newer)
    end
  end

  describe "after_commit #notify_followers_on_change" do
    let(:org) { create(:organization) }
    let(:bill) { create(:bill) }

    context "first activation (active false→true)" do
      it "enqueues NotifyOrganizationFollowersJob with change_types [:new_position] only (A1)" do
        # even when support and summary change at the same time
        position = create(:organization_bill_position,
          organization: org, bill: bill, active: false, support: "FOR", summary: "Draft")

        expect {
          position.update!(active: true, support: "AGAINST", summary: "Updated")
        }.to have_enqueued_job(NotifyOrganizationFollowersJob)
          .with(org.id, bill.id, ["new_position"], anything)
      end

      it "enqueues EXACTLY one job with EXACTLY [:new_position] — never support/summary (A1)" do
        # @lat: [[organization-bill-position-notification-callbacks#notify_followers_on_change: the guard and the change-label rule#Why the change-label spec asserts the exact arguments, not a negative]]
        position = create(:organization_bill_position,
          organization: org, bill: bill, active: false, support: "FOR", summary: "Draft")

        expect {
          position.update!(active: true, support: "AGAINST", summary: "New summary")
        }.to have_enqueued_job(NotifyOrganizationFollowersJob)
          .with(org.id, bill.id, ["new_position"], anything).exactly(:once)
      end
    end

    context "already-active position edits" do
      let(:position) do
        create(:organization_bill_position,
          organization: org, bill: bill, active: true, support: "FOR", summary: "Original")
      end

      it "enqueues [:support_change] on a support-only edit" do
        expect {
          position.update!(support: "AGAINST")
        }.to have_enqueued_job(NotifyOrganizationFollowersJob)
          .with(org.id, bill.id, ["support_change"], anything)
      end

      it "enqueues [:summary_change] on a summary-only edit" do
        expect {
          position.update!(summary: "Updated summary text")
        }.to have_enqueued_job(NotifyOrganizationFollowersJob)
          .with(org.id, bill.id, ["summary_change"], anything)
      end

      it "enqueues [:support_change, :summary_change] when both change" do
        expect {
          position.update!(support: "AGAINST", summary: "Reversed and updated")
        }.to have_enqueued_job(NotifyOrganizationFollowersJob)
          .with(org.id, bill.id, ["support_change", "summary_change"], anything)
      end
    end

    context "soft-delete (active→false)" do
      it "enqueues NOTHING when active flips to false (soft-delete guard)" do
        position = create(:organization_bill_position,
          organization: org, bill: bill, active: true, support: "FOR", summary: "Active")

        expect {
          position.update!(active: false)
        }.not_to have_enqueued_job(NotifyOrganizationFollowersJob)
      end
    end

    context "inactive-to-inactive save (active stays false)" do
      it "enqueues nothing when the position remains inactive" do
        position = create(:organization_bill_position,
          organization: org, bill: bill, active: false, support: "FOR", summary: "Draft")

        expect {
          position.update!(summary: "Still pending")
        }.not_to have_enqueued_job(NotifyOrganizationFollowersJob)
      end
    end
  end

  describe "the testimony a reader is shown" do
    let(:bill) { create(:bill) }

    # One organization per call: a bill may carry one position per organization.
    def position_with(support)
      create(:organization_bill_position,
        organization: create(:organization), bill: bill, support: support,
        summary: "Stored in the column.")
    end

    it "answers nil for a Neutral position and the column for one that takes a side" do
      expect(position_with("ABSTAIN").summary_for_readers).to be_nil
      expect(position_with("FOR").summary_for_readers).to eql("Stored in the column.")
    end

    it "sends no testimony through to_sway_json for a Neutral position" do
      expect(position_with("ABSTAIN").to_sway_json["summary"]).to be_nil
      expect(position_with("FOR").to_sway_json["summary"]).to eql("Stored in the column.")
    end

    it "sends no testimony through to_public_json for a Neutral position" do
      neutral = position_with("ABSTAIN")

      payload = neutral.to_public_json

      expect(payload[:summary]).to be_nil
      expect(payload.keys).to match_array(
        %i[id organization_id bill_id support summary active created_at summary_ai_unreviewed]
      )
      expect(position_with("FOR").to_public_json[:summary]).to eql("Stored in the column.")
    end
  end
end
