FactoryBot.define do
  factory :refresh_token do
    association :user
    token { SecureRandom.urlsafe_base64(32) }
    ip_address { "203.0.113.10" }
    user_agent { "RSpec Browser" }
    expires_at { 1.year.from_now }
  end
end
