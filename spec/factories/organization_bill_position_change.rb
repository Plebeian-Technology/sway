FactoryBot.define do
  factory :organization_bill_position_change do
    organization_bill_position
    # OrganizationBillPositionChange now validates new_support
    # against OrganizationBillPosition::STANCE_TO_SUPPORT.keys, so these can
    # no longer be placeholder booleans (Rails cast them to the strings
    # "true"/"false", neither a recognized stance).
    previous_support { "oppose" }
    new_support { "support" }
    previous_summary { "Initial summary" }
    new_summary { "New summary" }
    updated_by { association :user }
    approved_by_id { nil }
  end
end
