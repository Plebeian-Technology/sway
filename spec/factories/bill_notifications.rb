# == Schema Information
#
# Table name: bill_notifications
# Database name: primary
#
#  id         :integer          not null, primary key
#  created_at :datetime         not null
#  updated_at :datetime         not null
#  bill_id    :integer          not null
#
# Indexes
#
#  index_bill_notifications_on_bill_id  (bill_id) UNIQUE
#
# Foreign Keys
#
#  bill_id  (bill_id => bills.id)
#
FactoryBot.define do
  factory :bill_notification do
    bill
  end
end
