# frozen_string_literal: true
# typed: strict

# == Schema Information
#
# Table name: user_votes
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
  after_commit :update_scores

  validates :support, inclusion: {in: %w[FOR AGAINST]}

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
    support == "FOR"
  end

  sig { returns(T::Boolean) }
  def against?
    support == "AGAINST"
  end

  private

  # Update BillScore, BillScoreDistrict and UserLegislatorScore
  sig { returns(T.untyped) }
  def update_scores
    ScoreUpdaterService.new(self).run
  end

  sig { void }
  def upcase_support
    self.support = support.upcase.strip
  end
end
