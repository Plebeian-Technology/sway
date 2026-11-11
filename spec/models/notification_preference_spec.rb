# frozen_string_literal: true

# == Schema Information
#
# Table name: notification_preferences
# Database name: primary
#
#  id         :integer          not null, primary key
#  enabled    :boolean          default(FALSE), not null
#  key        :string           not null
#  created_at :datetime         not null
#  updated_at :datetime         not null
#  user_id    :integer          not null
#
# Indexes
#
#  index_notification_preferences_on_user_id_and_key  (user_id,key) UNIQUE
#
# Foreign Keys
#
#  user_id  (user_id => users.id)
#
require "rails_helper"

RSpec.describe NotificationPreference, type: :model do
  describe "validations" do
    it "requires a user" do
      pref = NotificationPreference.new(key: "botm_announcement", enabled: true)
      expect(pref).not_to be_valid
      expect(pref.errors[:user]).to be_present
    end

    it "validates key is one of the allowed KEYS" do
      user = create(:user)
      bad = NotificationPreference.new(user: user, key: "not_a_real_key", enabled: false)
      expect(bad).not_to be_valid
      expect(bad.errors[:key]).to be_present

      NotificationPreference::KEYS.each do |k|
        good = NotificationPreference.new(user: user, key: k, enabled: false)
        expect(good).to be_valid, "expected #{k} to be valid"
      end
    end

    it "validates uniqueness of key scoped to user" do
      user = create(:user)
      create(:notification_preference, user: user, key: "botm_announcement")

      dup = NotificationPreference.new(user: user, key: "botm_announcement", enabled: false)
      expect(dup).not_to be_valid
      expect(dup.errors[:key]).to be_present
    end

    it "allows the same key for a different user" do
      user1 = create(:user)
      user2 = create(:user)
      create(:notification_preference, user: user1, key: "botm_announcement")

      other = NotificationPreference.new(user: user2, key: "botm_announcement", enabled: true)
      expect(other).to be_valid
    end
  end

  describe "constants" do
    it "defines CANONICAL_KEYS with botm_announcement as canonical" do
      expect(NotificationPreference::CANONICAL_KEYS).to eq(
        %w[botm_announcement legislator_voted vote_window_closing org_position_taken legislator_updates]
      )
      expect(NotificationPreference::KEYS).to eq(NotificationPreference::CANONICAL_KEYS)
    end
  end

  describe ".seed_defaults_for" do
    it "creates exactly 5 rows with defaults (botm on, others off)" do
      user = create(:user)
      NotificationPreference.seed_defaults_for(user)

      prefs = user.notification_preferences.reload
      expect(prefs.size).to eq(5)
      expect(prefs.pluck(:key)).to match_array(NotificationPreference::CANONICAL_KEYS)

      expected = {
        "botm_announcement" => true,
        "legislator_voted" => false,
        "vote_window_closing" => false,
        "org_position_taken" => false,
        "legislator_updates" => false
      }
      prefs.each do |p|
        expect(p.enabled).to eq(expected[p.key]), "expected #{p.key} enabled=#{expected[p.key]}, got #{p.enabled}"
      end
    end

    it "is idempotent (calling twice still leaves exactly 5 rows)" do
      user = create(:user)
      NotificationPreference.seed_defaults_for(user)
      NotificationPreference.seed_defaults_for(user)

      expect(user.notification_preferences.reload.size).to eq(5)
    end

    it "preserves an existing opt-out on botm_announcement when re-seeded" do
      user = create(:user)
      create(:notification_preference, user: user, key: "botm_announcement", enabled: false)
      NotificationPreference.seed_defaults_for(user)

      pref = user.notification_preferences.reload.find_by(key: "botm_announcement")
      expect(pref.enabled).to be(false)
    end
  end
end
