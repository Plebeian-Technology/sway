# frozen_string_literal: true

# == Schema Information
#
# Table name: bill_score_districts
# Database name: primary
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
  include Supportable
  include Scoreable

  belongs_to :bill_score
  belongs_to :district

  def bill_score
    super
  end

  def district
    super
  end

  def update_score(user_vote)
    update_supportable_score(user_vote)
    save!
    self
  end

  def to_builder
    Jbuilder.new do |bsd|
      bsd.bill_score_id bill_score_id
      bsd.district district.to_sway_json
      bsd.for self.for
      bsd.against against
    end
  end
end
