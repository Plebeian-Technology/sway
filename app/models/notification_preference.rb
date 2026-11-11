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
class NotificationPreference < ApplicationRecord
  CANONICAL_KEYS = %w[
    botm_announcement
    legislator_voted
    vote_window_closing
    org_position_taken
    legislator_updates
  ].freeze

  KEYS = CANONICAL_KEYS

  belongs_to :user

  validates :key,
    presence: true,
    inclusion: {in: CANONICAL_KEYS},
    uniqueness: {scope: :user_id}

  def self.seed_defaults_for(user)
    CANONICAL_KEYS.each do |k|
      find_or_create_by!(user: user, key: k) do |np|
        np.enabled = (k == "botm_announcement")
      end
    end
  end
end
