FactoryBot.define do
  factory :organization_bill_position do
    association :organization
    association :bill
    support { "support" }
    summary { "This is a summary of the organization's position on the bill." }
  end
end
