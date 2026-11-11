FactoryBot.define do
  factory :user_legislator_email do
    user_legislator
    bill

    initialize_with { new({user_legislator:, bill:}) }
  end
end
