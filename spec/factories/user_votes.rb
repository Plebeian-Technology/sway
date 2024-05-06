# == Schema Information
#
# Table name: user_votes
#
#  id         :integer          not null, primary key
#  user_id    :integer          not null
#  bill_id    :integer          not null
#  support    :string           not null
#  created_at :datetime         not null
#  updated_at :datetime         not null
#
FactoryBot.define do
  factory :user_vote do
    user
    bill
    support { 'for' }

    initialize_with { new({ user:, bill:, support: }) }
  end
end
