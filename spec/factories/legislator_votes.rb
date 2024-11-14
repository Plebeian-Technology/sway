# == Schema Information
#
# Table name: legislator_votes
#
#  id            :integer          not null, primary key
#  support       :string           not null
#  created_at    :datetime         not null
#  updated_at    :datetime         not null
#  bill_id       :integer          not null
#  legislator_id :integer          not null
#
# Indexes
#
#  index_legislator_votes_on_bill_id        (bill_id)
#  index_legislator_votes_on_legislator_id  (legislator_id)
#
# Foreign Keys
#
#  bill_id        (bill_id => bills.id)
#  legislator_id  (legislator_id => legislators.id)
#
FactoryBot.define do
  factory :legislator_vote do
    bill
    legislator
    support { "for" }

    initialize_with { new({bill:, legislator:, support:}) }
  end
end
