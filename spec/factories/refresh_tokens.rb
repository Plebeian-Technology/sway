# == Schema Information
#
# Table name: refresh_tokens
# Database name: primary
#
#  id         :integer          not null, primary key
#  expires_at :datetime         not null
#  ip_address :string           not null
#  token      :string           not null
#  user_agent :string           not null
#  created_at :datetime         not null
#  updated_at :datetime         not null
#  user_id    :integer          not null
#
# Indexes
#
#  index_refresh_tokens_on_token    (token) UNIQUE
#  index_refresh_tokens_on_user_id  (user_id)
#
# Foreign Keys
#
#  user_id  (user_id => users.id)
#
FactoryBot.define do
  factory :refresh_token do
    association :user
    token { SecureRandom.urlsafe_base64(32) }
    ip_address { "203.0.113.10" }
    user_agent { "RSpec Browser" }
    expires_at { 1.year.from_now }
  end
end
