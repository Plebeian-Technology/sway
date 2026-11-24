# frozen_string_literal: true

require "rails_helper"
require Rails.root.join("db", "migrate", "20261124171036_rename_origin_to_source_on_organization_bill_positions")

RSpec.describe "RenameOriginToSourceOnOrganizationBillPositions migration", type: :model do
  let(:migration) { RenameOriginToSourceOnOrganizationBillPositions.new }
  let(:member) { create(:user) }

  def position_with_approved_change(position_written_at:, change_approved_at:)
    position = create(:organization_bill_position, organization: create(:organization, name: SecureRandom.hex(6)))
    change = create(:organization_bill_position_change,
      organization_bill_position: position, updated_by: member, status: :pending)
    change.update_columns(status: OrganizationBillPositionChange.statuses[:approved],
      approved_by_id: member.id, updated_at: change_approved_at)
    position.update_columns(updated_at: position_written_at, source_kind: nil)
    position
  end

  def backfill
    ActiveRecord::Migration.suppress_messages { migration.backfill_organization_source_kind }
  end

  it "marks a position whose latest write was an approved change as written by the organization" do
    approved_at = 2.days.ago
    position = position_with_approved_change(position_written_at: approved_at + 0.01, change_approved_at: approved_at)

    backfill

    expect(position.reload.source_kind).to eq("organization")
  end

  it "leaves a position alone when a later write replaced the approved change" do
    approved_at = 2.days.ago
    position = position_with_approved_change(position_written_at: 1.day.ago, change_approved_at: approved_at)

    backfill

    expect(position.reload.source_kind).to be_nil
  end

  it "leaves a position alone when its only change is still pending" do
    position = create(:organization_bill_position)
    create(:organization_bill_position_change,
      organization_bill_position: position, updated_by: member, status: :pending)

    backfill

    expect(position.reload.source_kind).to be_nil
  end

  it "leaves a position with no changes alone" do
    position = create(:organization_bill_position)

    backfill

    expect(position.reload.source_kind).to be_nil
  end
end
