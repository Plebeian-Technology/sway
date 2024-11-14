# == Schema Information
#
# Table name: user_legislators
#
#  id            :integer          not null, primary key
#  created_at    :datetime         not null
#  updated_at    :datetime         not null
#  legislator_id :integer          not null
#  user_id       :integer          not null
#
# Indexes
#
#  index_user_legislators_on_legislator_id  (legislator_id)
#  index_user_legislators_on_user_id        (user_id)
#
# Foreign Keys
#
#  legislator_id  (legislator_id => legislators.id)
#  user_id        (user_id => users.id)
#
FactoryBot.define do
  factory :user_legislator do
    user
    legislator

    initialize_with { new({user:, legislator:}) }
  end
end
