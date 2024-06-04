# == Schema Information
#
# Table name: legislator_votes
#
#  id            :integer          not null, primary key
#  legislator_id :integer          not null
#  bill_id       :integer          not null
#  support       :string           not null
#  created_at    :datetime         not null
#  updated_at    :datetime         not null
#
FactoryBot.define do
  factory :legislator_vote do
    bill
    legislator
    support { 'for' }

    initialize_with { new({ bill:, legislator:, support: }) }
  end
end
