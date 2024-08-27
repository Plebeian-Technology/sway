# frozen_string_literal: true
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
  include Supportable
  include Scoreable

  belongs_to :bill

  has_many :bill_score_districts, dependent: :destroy

  sig { returns(Bill) }
  def bill
    T.cast(super, Bill)
  end

  sig { override.params(user_vote: UserVote).returns(BillScore) }
  def update_score(user_vote)
    update_supportable_score(user_vote)
    save!
    self
  end

  sig { returns(Jbuilder) }
  def to_builder
    Jbuilder.new do |bs|
      bs.bill_id bill_id
      bs.for self.for
      bs.against against
      bs.districts(bill_score_districts.map { |bsd| bsd.to_builder.attributes! })
    end
  end
end
