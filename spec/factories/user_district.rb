FactoryBot.define do
  factory :user_district do
    user
    district

    initialize_with { new({ user:, district: }) }
  end
end
