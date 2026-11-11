# frozen_string_literal: true

# == Schema Information
#
# Table name: user_bill_shares
# Database name: primary
#
#  id          :integer          not null, primary key
#  redeemed_at :datetime
#  share_uuid  :string           not null
#  created_at  :datetime         not null
#  updated_at  :datetime         not null
#  bill_id     :integer          not null
#  user_id     :integer          not null
#
# Indexes
#
#  index_user_bill_shares_on_bill_id              (bill_id)
#  index_user_bill_shares_on_share_uuid           (share_uuid) UNIQUE
#  index_user_bill_shares_on_user_id_and_bill_id  (user_id,bill_id) UNIQUE
#
# Foreign Keys
#
#  bill_id  (bill_id => bills.id)
#  user_id  (user_id => users.id)
#
FactoryBot.define do
  factory :user_bill_share do
    user
    bill
    add_attribute(:redeemed_at) { nil }

    trait :redeemed do
      add_attribute(:redeemed_at) { Time.current }
    end
  end
end
