FactoryBot.define do
  factory :passkey do
    association :user
    external_id { SecureRandom.uuid }
    public_key { SecureRandom.hex }
    label { "Test Passkey" }
    sign_count { 0 }
  end
end
