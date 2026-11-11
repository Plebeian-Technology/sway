FactoryBot.define do
  factory :user_invite_link do
    user

    initialize_with { new({user:}) }
  end
end
