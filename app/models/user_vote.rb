# frozen_string_literal: true
# typed: strict

# == Schema Information
#
# Table name: user_votes
#
#  id         :integer          not null, primary key
#  support    :string           not null
#  created_at :datetime         not null
#  updated_at :datetime         not null
#  bill_id    :integer          not null
#  user_id    :integer          not null
#
# Indexes
#
#  index_user_votes_on_bill_id  (bill_id)
#  index_user_votes_on_user_id  (user_id)
#
# Foreign Keys
#
#  bill_id  (bill_id => bills.id)
#  user_id  (user_id => users.id)
#
#  id         :integer          not null, primary key
#  user_id    :integer          not null
#  bill_id    :integer          not null
#  support    :string           not null
#  created_at :datetime         not null
#  updated_at :datetime         not null

class UserVote < ApplicationRecord
  extend T::Sig

  belongs_to :user
  belongs_to :bill

  after_initialize :upcase_support
  after_create_commit :update_scores

  validates :support, inclusion: {in: LegislatorVote::Support::FOR_AGAINST}
  validates :user, :bill, presence: {message: "can't be blank"}

  sig { returns(Bill) }
  def bill
    T.cast(super, Bill)
  end

  sig { returns(User) }
  def user
    T.cast(super, User)
  end

  sig { returns(T::Boolean) }
  def for?
    support == LegislatorVote::Support::FOR
  end

  sig { returns(T::Boolean) }
  def against?
    support == LegislatorVote::Support::AGAINST
  end

  private

  # Update BillScore, BillScoreDistrict and UserLegislatorScore
  sig { returns(T.untyped) }
  def update_scores
    OnUserVoteUpdateScoresJob.perform_later(self)
  end

  sig { void }
  def upcase_support
    self.support = support.upcase.strip
  end
end
