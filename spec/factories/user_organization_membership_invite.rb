FactoryBot.define do
  factory :user_organization_membership_invite do
    inviter factory: :user
    organization
    invitee_email { "invitee@example.com" }

    trait :expired do
      expires_at { 1.day.ago }
    end

    trait :revoked do
      revoked_at { Time.current }
    end

    trait :accepted do
      accepted_at { Time.current }
      invitee_user factory: :user
    end
  end
end
