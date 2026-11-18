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
#  index_bill_score_districts_on_bs_and_district  (bill_score_id,district_id) UNIQUE
#  index_bill_score_districts_on_district_id      (district_id)
#
# Foreign Keys
#
#  bill_score_id  (bill_score_id => bill_scores.id)
#  district_id    (district_id => districts.id)
#
class BillScoreDistrict < ApplicationRecord
  belongs_to :bill_score
  belongs_to :district

  def to_builder
    Jbuilder.new do |bsd|
      bsd.bill_score_id bill_score_id
      bsd.district district.to_sway_json
      bsd.for self.for
      bsd.against against
      bsd.comparison_suppressed VoteComparisonPrivacy.suppressed?(self.for, against)
      bsd.for_percent for_percent
      bsd.against_percent against_percent
      bsd.at_large at_large?
    end
  end

  def at_large?
    # @lat: [[scores-and-agreement#An at-large official has no district tally worth drawing]]
    district.at_large?
  end

  def for_percent
    return nil if VoteComparisonPrivacy.suppressed?(self.for, against)

    total = self.for + against
    return 0 if total.zero?

    ((self.for.to_f / total) * 100).round
  end

  def against_percent
    return nil if VoteComparisonPrivacy.suppressed?(self.for, against)

    total = self.for + against
    return 0 if total.zero?

    ((against.to_f / total) * 100).round
  end
end
