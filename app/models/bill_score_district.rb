# frozen_string_literal: true
# typed: strict

# == Schema Information
#
# Table name: bill_score_districts
#
#  id            :integer          not null, primary key
#  bill_score_id :integer          not null
#  district_id   :integer          not null
#  for           :integer          default(0), not null
#  against       :integer          default(0), not null
#  created_at    :datetime         not null
#  updated_at    :datetime         not null
#
class BillScoreDistrict < ApplicationRecord
  extend T::Sig
  include Supportable
  include Scoreable

  belongs_to :bill_score
  belongs_to :district

  sig { returns(BillScore) }
  def bill_score
    T.cast(super, BillScore)
  end

  sig { returns(District) }
  def district
    T.cast(super, District)
  end

  sig { override.params(user_vote: UserVote).returns(BillScoreDistrict) }
  def update_score(user_vote)
    update_supportable_score(user_vote)
    save!
    self
  end

  sig { returns(Jbuilder) }
  def to_builder
    Jbuilder.new do |bsd|
      bsd.bill_score_id bill_score_id
      bsd.district district.to_builder
      bsd.for self.for
      bsd.against against
    end
  end
end
