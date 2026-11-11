# frozen_string_literal: true

class InfluenceService
  def initialize(user:, sway_locale:)
    @user = user
    @sway_locale = sway_locale
  end

  # @lat: [[scores-and-agreement#Sway is a separate quantity]]
  def to_builder
    count_invites_redeemed = count_invites_where_inviter_is_user
    count_bills_voted_on = count_user_votes_by_locale
    count_bills_shared = count_user_bill_shares_by_locale
    Jbuilder.new do |i|
      i.count_invites_redeemed count_invites_redeemed
      i.count_bills_voted_on count_bills_voted_on
      i.count_bills_shared count_bills_shared
      i.total_sway count_invites_redeemed + count_bills_voted_on + count_bills_shared
    end
  end

  private

  def count_user_votes_by_locale
    UserVote
      .joins(:bill)
      .where(user_id: @user.id, bills: {sway_locale_id: @sway_locale.id})
      .count
  end

  def count_user_bill_shares_by_locale
    UserBillShare
      .redeemed
      .joins(:bill)
      .where(user_id: @user.id, bills: {sway_locale_id: @sway_locale.id})
      .count
  end

  def count_invites_where_inviter_is_user
    Invite.where(inviter_id: @user.id).count
  end
end
