# frozen_string_literal: true

require "rails_helper"

# Unit tests for the soft-reject logic pulled out of
# PositionChangesController#destroy. The controller's request spec covers
# HTTP and the audit log; these pin the service return.
RSpec.describe RejectPositionChangeService do
  it "soft-rejects a pending change and stamps the rejecter" do
    rejecter = create(:user)
    organization = create(:organization)
    position = create(:organization_bill_position, organization: organization)
    change = create(:organization_bill_position_change,
      organization_bill_position: position, updated_by: rejecter, status: :pending)

    outcome = described_class.new(change: change, rejecter: rejecter).call

    expect(outcome).to eq(:rejected)
    expect(change.reload.status).to eq("rejected")
    expect(change.rejected_by_id).to eq(rejecter.id)
    expect(change.rejected_at).to be_within(5.seconds).of(Time.current)
  end

  it "returns :already_finalized and mutates nothing when already approved" do
    rejecter = create(:user)
    organization = create(:organization)
    position = create(:organization_bill_position, organization: organization)
    change = create(:organization_bill_position_change,
      organization_bill_position: position, updated_by: rejecter, status: :pending)
    change.update!(approved_by: rejecter, status: :approved)

    outcome = described_class.new(change: change, rejecter: rejecter).call

    expect(outcome).to eq(:already_finalized)
    expect(change.reload.status).to eq("approved")
    expect(change.rejected_by_id).to be_nil
    expect(change.rejected_at).to be_nil
  end

  it "returns :already_finalized when already rejected (idempotent)" do
    rejecter = create(:user)
    organization = create(:organization)
    position = create(:organization_bill_position, organization: organization)
    change = create(:organization_bill_position_change,
      organization_bill_position: position, updated_by: rejecter, status: :pending)
    original_time = 1.day.ago
    change.update!(rejected_by: rejecter, rejected_at: original_time, status: :rejected)

    expect(described_class.new(change: change, rejecter: rejecter).call).to eq(:already_finalized)
    expect(change.reload.rejected_at).to be_within(1.second).of(original_time)
  end
end
