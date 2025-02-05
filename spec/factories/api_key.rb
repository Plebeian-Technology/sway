# typed: true

FactoryBot.define do
  factory :api_key do
    name { Faker::ProgrammingLanguage.name }
    token { SecureRandom.hex }
    last_used_on_utc { nil }
    bearer_type { "User" }

    association :bearer, factory: :user

    initialize_with {
      new({
        name:,
        token:,
        last_used_on_utc:,
        bearer_type:
      })
    }
  end
end
