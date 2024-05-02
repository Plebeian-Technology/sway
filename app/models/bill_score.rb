# typed: true

# == Schema Information
#
# Table name: bill_scores
#
#  id         :integer          not null, primary key
#  bill_id    :integer          not null
#  for        :integer          default(0), not null
#  against    :integer          default(0), not null
#  created_at :datetime         not null
#  updated_at :datetime         not null
#

class BillScore < ApplicationRecord
  extend T::Sig
  include ::Scoreable

  belongs_to :bill

  has_many :bill_score_districts

  sig { returns(Bill) }
  def bill
    T.cast(super, Bill)
  end

  sig { override.params(user_vote: UserVote).returns(BillScore) }
  def update_score(user_vote)
    self.for = self.for + 1 if user_vote.for?
    self.against = against + 1 if user_vote.against?
    save!
    self
  end

  sig { returns(Jbuilder) }
  def to_builder
    Jbuilder.new do |bs|
      bs.bill_id bill_id
      bs.for :for
      bs.against against
    end
  end
end
