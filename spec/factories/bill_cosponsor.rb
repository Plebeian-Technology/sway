FactoryBot.define do
  factory :bill_cosponsor do
    bill
    legislator

    initialize_with { new({bill:, legislator:}) }
  end
end
