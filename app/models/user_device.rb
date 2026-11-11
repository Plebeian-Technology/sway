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
class UserDevice < ApplicationRecord
  PLATFORMS = %w[ios android].freeze

  belongs_to :user
  has_many :api_keys, dependent: :destroy

  validates :platform, presence: true, inclusion: {in: PLATFORMS}
  validates :last_seen_at, presence: true

  scope :active, -> { where(revoked_at: nil) }
  scope :with_push, -> { active.where.not(push_token: nil) }

  # @lat: [[api-key-hmac-secret-handling#Why UserDevice.revoke! expires keys in the same transaction]]
  def revoke!
    now = Time.current
    transaction do
      update!(revoked_at: now)
      api_keys.update_all(expires_at: now)
    end
  end
end
