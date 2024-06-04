# == Schema Information
#
# Table name: user_addresses
#
#  id         :integer          not null, primary key
#  address_id :integer          not null
#  user_id    :integer          not null
#  created_at :datetime         not null
#  updated_at :datetime         not null
#
FactoryBot.define do
  factory :user_address do
    user
    address

    initialize_with { new({ user:, address: }) }
  end
end
