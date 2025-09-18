FactoryBot.define do
  factory :organization_bill_position_change do
    association :organization_bill_position
    previous_support { false }
    new_support { true }
    previous_summary { "Initial summary" }
    new_summary { "New summary" }
    updated_by { association :user }
    approved_by_id { nil }
  end
end
