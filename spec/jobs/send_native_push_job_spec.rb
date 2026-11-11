# frozen_string_literal: true

require "rails_helper"

RSpec.describe SendNativePushJob, type: :job do
  let(:user) { create(:user) }
  let(:device) do
    create(:user_device, user: user, platform: "android", push_token: "tok")
  end
  let(:payload) { {kind: "botm_announcement", title: "T", body: "B", data: {bill_id: 1}} }

  before do
    create(:notification_preference, user: user, key: "botm_announcement", enabled: true)
  end

  it "dispatches via NativePushDispatcher when pref enabled" do
    expect(NativePushDispatcher).to receive(:deliver).with(device, payload)
    described_class.new.perform(device.id, payload)
  end

  it "skips when device is revoked" do
    device.revoke!
    expect(NativePushDispatcher).not_to receive(:deliver)
    described_class.new.perform(device.id, payload)
  end

  it "skips when push_token is blank" do
    device.update_columns(push_token: nil)
    expect(NativePushDispatcher).not_to receive(:deliver)
    described_class.new.perform(device.id, payload)
  end

  it "skips when notification preference is disabled" do
    user.notification_preferences.find_by(key: "botm_announcement").update!(enabled: false)
    expect(NativePushDispatcher).not_to receive(:deliver)
    described_class.new.perform(device.id, payload)
  end

  it "skips when notification preference is missing" do
    user.notification_preferences.destroy_all
    expect(NativePushDispatcher).not_to receive(:deliver)
    described_class.new.perform(device.id, payload)
  end

  it "calls revoke! on receipt-based DeviceNotRegisteredError" do
    allow(NativePushDispatcher).to receive(:deliver)
      .and_raise(NativePushDispatcher::DeviceNotRegisteredError)
    expect {
      described_class.new.perform(device.id, payload)
    }.to change { device.reload.revoked_at }.from(nil)
  end

  it "is a no-op when device record was deleted" do
    expect {
      described_class.new.perform(999_999_999, payload)
    }.not_to raise_error
  end

  # The branch where a "test_push" ignores the user's notification settings.
  context "with kind: \"test_push\" payload" do
    let(:test_payload) { {kind: "test_push", title: "Test", body: "Sway test"} }

    it "bypasses pref-gate when kind is test_push (no preference row exists)" do
      user.notification_preferences.destroy_all
      expect(NativePushDispatcher).to receive(:deliver).with(device, test_payload).once
      described_class.new.perform(device.id, test_payload)
    end

    it "bypasses pref-gate when ALL preferences are disabled" do
      NotificationPreference::KEYS.each do |k|
        user.notification_preferences.find_or_create_by!(key: k).update!(enabled: false)
      end
      expect(NativePushDispatcher).to receive(:deliver).with(device, test_payload).once
      described_class.new.perform(device.id, test_payload)
    end

    it "still applies pref-gate for non-test kinds (regression guard)" do
      user.notification_preferences.find_by(key: "botm_announcement").update!(enabled: false)
      expect(NativePushDispatcher).not_to receive(:deliver)
      described_class.new.perform(device.id, payload)
    end

    it "still skips test_push when device is revoked" do
      device.revoke!
      expect(NativePushDispatcher).not_to receive(:deliver)
      described_class.new.perform(device.id, test_payload)
    end

    it "still skips test_push when push_token is blank" do
      device.update_columns(push_token: nil)
      expect(NativePushDispatcher).not_to receive(:deliver)
      described_class.new.perform(device.id, test_payload)
    end
  end

  context "with monthly featured-bill notification contract" do
    let(:payload) { {kind: "botm_announcement", title: "New Bill of the Month", body: "B", data: {bill_id: 1}} }

    it "dispatches when canonical botm_announcement is enabled" do
      user.notification_preferences.destroy_all
      create(:notification_preference, user: user, key: "botm_announcement", enabled: true)
      expect(NativePushDispatcher).to receive(:deliver).with(device, payload)
      described_class.new.perform(device.id, payload)
    end

    it "skips when canonical botm_announcement is disabled" do
      user.notification_preferences.destroy_all
      create(:notification_preference, user: user, key: "botm_announcement", enabled: false)
      expect(NativePushDispatcher).not_to receive(:deliver)
      described_class.new.perform(device.id, payload)
    end
  end
end
