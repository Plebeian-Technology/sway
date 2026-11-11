# frozen_string_literal: true

# @lat: [[domain-entities#People and identity]]
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
class UserBillShare < ApplicationRecord
  belongs_to :user
  belongs_to :bill

  before_validation :assign_share_uuid, on: :create

  validates :bill_id, uniqueness: {scope: :user_id}
  validates :share_uuid, presence: true, uniqueness: true

  scope :redeemed, -> { where.not(redeemed_at: nil) }

  def redeemed?
    redeemed_at.present?
  end

  def share_path
    "/bill_shares/#{share_uuid}"
  end

  def redeem!(opener: nil)
    return false if opener&.id == user_id

    if redeemed_at.nil?
      now = Time.zone.now
      self.class.where(id:, redeemed_at: nil).update_all(redeemed_at: now, updated_at: now)
      self.redeemed_at = now
    end
    true
  end

  private

  def assign_share_uuid
    self.share_uuid = SecureRandom.uuid if share_uuid.blank?
  end
end
