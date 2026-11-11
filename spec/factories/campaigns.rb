# == Schema Information
#
# Table name: campaigns
# Database name: primary
#
#  id                         :integer          not null, primary key
#  active                     :boolean          default(FALSE), not null
#  ai_summary                 :text
#  icon_url                   :string
#  letter_count               :integer
#  name                       :string
#  organization_link_decision :string
#  sender_count               :integer
#  source_campaign_draft_hash :string
#  summary                    :text             not null
#  support                    :string           not null
#  created_at                 :datetime         not null
#  updated_at                 :datetime         not null
#  bill_id                    :integer          not null
#  organization_id            :integer
#
# Indexes
#
#  index_campaigns_on_bill_and_name               (bill_id,name) UNIQUE WHERE name IS NOT NULL
#  index_campaigns_on_bill_id                     (bill_id)
#  index_campaigns_on_organization_id             (organization_id)
#  index_campaigns_on_organization_link_decision  (organization_link_decision)
#
# Foreign Keys
#
#  bill_id          (bill_id => bills.id)
#  organization_id  (organization_id => organizations.id)
#
FactoryBot.define do
  factory :campaign do
    # A campaign may stay unnamed — "324 people sent this
    # letter" is a whole record on its own. The sequence keeps two factory
    # calls on the same bill from colliding on the partial unique index.
    sequence(:name) { |n| "Taco Campaign #{n}" }
    bill
    support { "FOR" }
    summary { "This is a summary of the campaign's position on the bill." }
    active { true }

    trait :unnamed do
      name { nil }
    end
  end
end
