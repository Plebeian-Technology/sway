# frozen_string_literal: true

require "rails_helper"

# Tests the approval rules pulled out of
# Organizations::PositionChangesController#update. The request spec covers
# HTTP mapping; these pin what the service returns and changes.
RSpec.describe ApprovePositionChangeService do
  it "approves a pending change and writes the proposal onto the live position" do
    approver = create(:user)
    organization = create(:organization)
    position = create(:organization_bill_position,
      organization: organization, support: "support", summary: "Original summary", active: false)
    change = create(:organization_bill_position_change,
      organization_bill_position: position, updated_by: approver,
      new_support: "oppose", new_summary: "Proposed summary", status: :pending)

    outcome = described_class.new(change: change, approver: approver).call

    expect(outcome).to eq(:approved)
    expect(change.reload.status).to eq("approved")
    expect(change.approved_by_id).to eq(approver.id)
    expect(position.reload.support).to eq(change.new_support)
    expect(position.summary).to eq("Proposed summary")
    expect(position.active).to be(true)
  end

  it "records the approved position as written by the organization, replacing a Sway-compiled origin" do
    approver = create(:user)
    position = create(:organization_bill_position,
      organization: create(:organization), source_kind: "news_article", source_url: "https://example.com/article")
    change = create(:organization_bill_position_change,
      organization_bill_position: position, updated_by: approver, status: :pending)

    described_class.new(change: change, approver: approver).call

    expect(position.reload.source_kind).to eq("organization")
    expect(position.source_url).to be_nil
  end

  it "returns :already_finalized and mutates nothing when the change was already approved" do
    approver = create(:user)
    organization = create(:organization)
    position = create(:organization_bill_position,
      organization: organization, summary: "Original summary")
    change = create(:organization_bill_position_change,
      organization_bill_position: position, updated_by: approver, status: :pending)
    change.update!(approved_by: approver, status: :approved)
    position.update!(summary: "Original summary")

    outcome = described_class.new(change: change, approver: approver).call

    expect(outcome).to eq(:already_finalized)
    expect(position.reload.summary).to eq("Original summary")
  end

  it "returns :already_finalized when the change was already rejected" do
    approver = create(:user)
    organization = create(:organization)
    position = create(:organization_bill_position, organization: organization)
    change = create(:organization_bill_position_change,
      organization_bill_position: position, updated_by: approver, status: :pending)
    change.update!(rejected_by: approver, rejected_at: Time.current, status: :rejected)

    expect(described_class.new(change: change, approver: approver).call).to eq(:already_finalized)
    expect(change.reload.status).to eq("rejected")
  end
end
