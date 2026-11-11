# frozen_string_literal: true

# == Schema Information
#
# Table name: user_devices
# Database name: primary
#
#  id           :integer          not null, primary key
#  app_version  :string
#  last_seen_at :datetime         not null
#  platform     :string           not null
#  push_token   :string
#  revoked_at   :datetime
#  created_at   :datetime         not null
#  updated_at   :datetime         not null
#  user_id      :integer          not null
#
# Indexes
#
#  index_user_devices_on_push_token              (push_token)
#  index_user_devices_on_push_token_active       (push_token) UNIQUE WHERE revoked_at IS NULL
#  index_user_devices_on_user_id                 (user_id)
#  index_user_devices_on_user_id_and_revoked_at  (user_id,revoked_at)
#
# Foreign Keys
#
#  user_id  (user_id => users.id)
#
require "rails_helper"

RSpec.describe UserDevice, type: :model do
  describe "validations" do
    it "requires a user" do
      device = UserDevice.new(platform: "ios", last_seen_at: Time.current)
      expect(device).not_to be_valid
      expect(device.errors[:user]).to be_present
    end

    it "requires platform to be ios or android" do
      user = create(:user)
      bad = UserDevice.new(user: user, platform: "windows", last_seen_at: Time.current)
      expect(bad).not_to be_valid
      expect(bad.errors[:platform]).to be_present

      good_ios = UserDevice.new(user: user, platform: "ios", last_seen_at: Time.current)
      expect(good_ios).to be_valid

      good_android = UserDevice.new(user: user, platform: "android", last_seen_at: Time.current)
      expect(good_android).to be_valid
    end

    it "requires last_seen_at" do
      user = create(:user)
      device = UserDevice.new(user: user, platform: "ios")
      expect(device).not_to be_valid
      expect(device.errors[:last_seen_at]).to be_present
    end
  end

  describe "scopes" do
    let(:user) { create(:user) }

    it ".active returns only devices with revoked_at IS NULL" do
      active = create(:user_device, user: user)
      revoked = create(:user_device, user: user, revoked_at: Time.current)

      expect(UserDevice.active).to include(active)
      expect(UserDevice.active).not_to include(revoked)
    end

    it ".with_push returns active devices with a push_token" do
      with_token = create(:user_device, user: user, push_token: "abc123")
      no_token = create(:user_device, user: user, push_token: nil)
      revoked_with_token = create(:user_device, user: user, push_token: "def456", revoked_at: Time.current)

      result = UserDevice.with_push
      expect(result).to include(with_token)
      expect(result).not_to include(no_token)
      expect(result).not_to include(revoked_with_token)
    end
  end

  describe "#revoke!" do
    it "sets revoked_at and expires associated api_keys" do
      user = create(:user)
      device = create(:user_device, user: user)
      raw_token = SecureRandom.hex(16)
      api_key = ApiKey.create!(name: "k", token: raw_token, bearer: user, user_device: device)
      expect(api_key.expires_at).to be_nil

      freeze = Time.current
      allow(Time).to receive(:current).and_return(freeze)

      device.revoke!

      expect(device.reload.revoked_at).to be_within(1.second).of(freeze)
      expect(api_key.reload.expires_at).to be_within(1.second).of(freeze)
    end
  end

  describe "partial unique index on push_token" do
    it "prevents two ACTIVE devices from sharing the same push_token" do
      user1 = create(:user)
      user2 = create(:user)
      create(:user_device, user: user1, push_token: "shared-token")

      expect {
        create(:user_device, user: user2, push_token: "shared-token")
      }.to raise_error(ActiveRecord::RecordNotUnique)
    end

    it "allows reuse of push_token after a device is revoked" do
      user1 = create(:user)
      user2 = create(:user)
      old = create(:user_device, user: user1, push_token: "reusable-token")
      old.update_column(:revoked_at, Time.current)

      expect {
        create(:user_device, user: user2, push_token: "reusable-token")
      }.not_to raise_error
    end
  end
end
