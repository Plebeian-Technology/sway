# frozen_string_literal: true

# == Schema Information
#
# Table name: user_bill_reminders
# Database name: primary
#
#  id         :integer          not null, primary key
#  sent_at    :datetime
#  created_at :datetime         not null
#  updated_at :datetime         not null
#  bill_id    :integer          not null
#  user_id    :integer          not null
#
# Indexes
#
#  index_user_bill_reminders_on_bill_id  (bill_id)
#  index_user_bill_reminders_on_user_id  (user_id)
#
# Foreign Keys
#
#  bill_id  (bill_id => bills.id)
#  user_id  (user_id => users.id)
#
class UserBillReminder < ApplicationRecord
  belongs_to :user
  belongs_to :bill
end
