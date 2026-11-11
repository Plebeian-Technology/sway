# frozen_string_literal: true

# @lat: [[admin-bill-view-cookie-replacement#Why AdminBillView is a row, not a cookie]]
# == Schema Information
#
# Table name: admin_bill_views
# Database name: primary
#
#  id            :integer          not null, primary key
#  last_seen_at  :datetime         not null
#  created_at    :datetime         not null
#  updated_at    :datetime         not null
#  admin_user_id :integer          not null
#  bill_id       :integer          not null
#
# Indexes
#
#  index_admin_bill_views_on_admin_user_and_bill  (admin_user_id,bill_id) UNIQUE
#  index_admin_bill_views_on_bill_id              (bill_id)
#
# Foreign Keys
#
#  admin_user_id  (admin_user_id => users.id)
#  bill_id        (bill_id => bills.id)
#
class AdminBillView < ApplicationRecord
  belongs_to :admin_user, class_name: "User"
  belongs_to :bill

  validates :last_seen_at, presence: true
  validates :admin_user_id, uniqueness: {scope: :bill_id}
end
