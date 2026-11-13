# frozen_string_literal: true

# == Schema Information
#
# Table name: bill_views
# Database name: primary
#
#  id         :integer          not null, primary key
#  created_at :datetime         not null
#  updated_at :datetime         not null
#  bill_id    :integer          not null
#  user_id    :integer          not null
#
# Indexes
#
#  index_bill_views_on_bill_id              (bill_id)
#  index_bill_views_on_user_id_and_bill_id  (user_id,bill_id) UNIQUE
#
# Foreign Keys
#
#  bill_id  (bill_id => bills.id)
#  user_id  (user_id => users.id)
#
class BillView < ApplicationRecord
  belongs_to :user
  belongs_to :bill

  validates :bill_id, uniqueness: {scope: :user_id}

  def self.record_for(user:, bill:)
    return nil if user.nil? || bill.nil?

    insert({user_id: user.id, bill_id: bill.id}, unique_by: %i[user_id bill_id])
  end
end
