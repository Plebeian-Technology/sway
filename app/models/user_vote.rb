# frozen_string_literal: true

# == Schema Information
#
# Table name: user_votes
# Database name: primary
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
  belongs_to :user
  belongs_to :bill

  after_initialize :upcase_support
  before_save :upcase_support
  after_create_commit :update_scores

  validates :support, inclusion: { in: LegislatorVote::Support::FOR_AGAINST }
  validates :user, :bill, presence: { message: "can't be blank" }

  def bill
    super
  end

  def user
    super
  end

  def for?
    support == LegislatorVote::Support::FOR
  end

  def against?
    support == LegislatorVote::Support::AGAINST
  end

  private

  # Update BillScore, BillScoreDistrict and UserLegislatorScore
  def update_scores
    Rails.logger.info(
      "UserVote - #{id} - created. Creating job OnUserVoteUpdateScoresJob.",
    )
    OnUserVoteUpdateScoresJob.perform_later(self)
  end

  def upcase_support
    self.support = support.upcase.strip if support.present?
  end
end
