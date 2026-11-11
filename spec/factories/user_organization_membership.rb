FactoryBot.define do
  factory :user_organization_membership do
    user
    organization
    role { :standard }
    # Defaults to active, so older specs that never set a status keep working.
    # Ask for the :pending or :removed trait when you want those states.
    status { "active" }

    trait :admin do
      role { :admin }
    end

    trait :pending do
      status { "pending" }
    end

    trait :active do
      status { "active" }
    end

    trait :removed do
      status { "removed" }
    end
  end
end
