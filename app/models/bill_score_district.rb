# frozen_string_literal: true
# typed: strict

# == Schema Information
#
# Table name: bill_score_districts
#
#  id            :integer          not null, primary key
#  against       :integer          default(0), not null
#  for           :integer          default(0), not null
#  created_at    :datetime         not null
#  updated_at    :datetime         not null
#  bill_score_id :integer          not null
#  district_id   :integer          not null
#
# Indexes
#
#  index_bill_score_districts_on_bill_score_id  (bill_score_id)
#  index_bill_score_districts_on_district_id    (district_id)
#
# Foreign Keys
#
#  bill_score_id  (bill_score_id => bill_scores.id)
#  district_id    (district_id => districts.id)
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
