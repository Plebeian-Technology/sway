# == Schema Information
#
# Table name: user_votes
# Database name: primary
#
#  id         :integer          not null, primary key
#  support    :string           not null
#  created_at :datetime         not null
#  updated_at :datetime         not null
#  bill_id    :integer          not null
#  user_id    :integer          not null
#
# Indexes
#
#  index_user_votes_on_bill_id              (bill_id)
#  index_user_votes_on_user_id_and_bill_id  (user_id,bill_id) UNIQUE
#
# Foreign Keys
#
#  bill_id  (bill_id => bills.id)
#  user_id  (user_id => users.id)
#
FactoryBot.define do
  factory :user_vote do
    user
    bill
    support { LegislatorVote::Support::FOR }

    initialize_with { new({user:, bill:, support:}) }

    trait :against do
      support { LegislatorVote::Support::AGAINST }
    end

    trait :abstain do
      support { LegislatorVote::Support::ABSTAIN }
    end
  end
end
