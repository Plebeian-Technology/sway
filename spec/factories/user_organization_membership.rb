FactoryBot.define do
  factory :user_organization_membership do
    association :user
    association :organization
    role { :standard }

    trait :admin do
      role { :admin }
    end
  end
end
