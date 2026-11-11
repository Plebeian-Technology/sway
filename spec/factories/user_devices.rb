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
FactoryBot.define do
  factory :user_device do
    user
    platform { "ios" }
    push_token { SecureRandom.hex(16) }
    app_version { "1.0.0" }
    last_seen_at { Time.current }
  end
end
