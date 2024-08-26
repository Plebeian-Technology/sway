# frozen_string_literal: true
# typed: true

class InfluenceService
  extend T::Sig

  sig { params(user: User, sway_locale: SwayLocale).void }
  def initialize(user:, sway_locale:)
    @user = user
    @sway_locale = sway_locale
  end

  sig { returns(Jbuilder) }
  def to_builder
    count_invites_redeemed = count_invites_where_inviter_is_user
    count_bills_voted_on = count_user_votes_by_locale
    Jbuilder.new do |i|
      i.count_invites_redeemed count_invites_redeemed
      i.count_bills_voted_on count_bills_voted_on
      i.total_sway count_invites_redeemed + count_bills_voted_on
    end
  end

  private

  sig { returns(Integer) }
  def count_user_votes_by_locale
    UserVote.count { |uv| uv.user_id == @user.id && uv.bill.sway_locale_id == @sway_locale.id }
  end

  sig { returns(Integer) }
  def count_invites_where_inviter_is_user
    Invite.count { |invite| invite.inviter_id == @user.id }
  end
end
