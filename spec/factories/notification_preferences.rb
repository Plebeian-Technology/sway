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
FactoryBot.define do
  factory :notification_preference do
    user
    key { "botm_announcement" }
    enabled { true }
  end
end
