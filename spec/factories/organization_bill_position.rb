FactoryBot.define do
  factory :organization_bill_position do
    organization
    bill
    support { "support" }
    summary { "This is a summary of the organization's position on the bill." }
    active { true }
  end
end
