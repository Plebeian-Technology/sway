# frozen_string_literal: true

require "rails_helper"

RSpec.describe CleanupRevokedDevicesJob, type: :job do
  let(:user) { create(:user) }

  it "revokes a device whose api_key has expired but device.revoked_at is nil" do
    device = create(:user_device, user: user, push_token: "tok")
    expired_key = ApiKey.new(
      bearer: user,
      user_device: device,
      bearer_type: "User",
      expires_at: 1.hour.ago,
      token: SecureRandom.hex,
      name: "test"
    )
    expired_key.save!(validate: false)

    expect {
      described_class.new.perform
    }.to change { device.reload.revoked_at }.from(nil)
  end

  it "does NOT revoke a device whose api_keys are all unexpired (dormancy is NOT a revoke trigger)" do
    device = create(:user_device, user: user, push_token: "tok")
    fresh_key = ApiKey.new(
      bearer: user,
      user_device: device,
      bearer_type: "User",
      expires_at: 1.hour.from_now,
      token: SecureRandom.hex,
      name: "fresh"
    )
    fresh_key.save!(validate: false)

    described_class.new.perform
    expect(device.reload.revoked_at).to be_nil
  end

  it "does NOT revoke a device with no api_keys (purely-dormant device — receipt-based per MEDIUM fix)" do
    device = create(:user_device, user: user, push_token: "tok", last_seen_at: 200.days.ago)
    described_class.new.perform
    expect(device.reload.revoked_at).to be_nil
  end

  it "leaves already-revoked devices alone (revoke! is idempotent at the model layer but job should not re-touch)" do
    device = create(:user_device, user: user, push_token: "tok")
    device.update_columns(revoked_at: 1.day.ago)
    expired_key = ApiKey.new(
      bearer: user,
      user_device: device,
      bearer_type: "User",
      expires_at: 1.hour.ago,
      token: SecureRandom.hex,
      name: "test"
    )
    expired_key.save!(validate: false)

    expect {
      described_class.new.perform
    }.not_to(change { device.reload.revoked_at })
  end
end
