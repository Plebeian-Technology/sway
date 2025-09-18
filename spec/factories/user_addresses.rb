# == Schema Information
#
# Table name: user_addresses
#
#  id         :integer          not null, primary key
#  created_at :datetime         not null
#  updated_at :datetime         not null
#  address_id :integer          not null
#  user_id    :integer          not null
#
# Indexes
#
#  index_user_addresses_on_address_id  (address_id)
#  index_user_addresses_on_user_id     (user_id)
#
# Foreign Keys
#
#  address_id  (address_id => addresses.id)
#  user_id     (user_id => users.id)
#
FactoryBot.define do
  factory :user_address do
    user
    address

    initialize_with { new({ user:, address: }) }
  end
end
