FactoryBot.define do
    factory :user_organization_membership_invite do
        association :inviter, factory: :user
        association :organization
        invitee_email { "invitee@example.com" }
        # Add role if your model supports it, e.g.:
        # role { :standard }
    end
end
