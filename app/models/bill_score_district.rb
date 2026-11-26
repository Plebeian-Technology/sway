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

  # @lat: [[voter-privacy-threshold#No endpoint sends a count that could identify a voter]]
  def to_builder
    Jbuilder.new do |bsd|
      bsd.bill_score_id bill_score_id
      bsd.district district.to_sway_json
      bsd.comparison_suppressed comparison_suppressed?
      bsd.for_percent for_percent
      bsd.against_percent against_percent
      bsd.at_large at_large?
    end
  end

  def comparison_suppressed?
    VoteComparisonPrivacy.withheld?(self.for, against)
  end

  # @lat: [[voter-privacy-threshold#No endpoint sends a count that could identify a voter]]
  def publishable?
    !comparison_suppressed? && !at_large?
  end

  # @lat: [[scores-and-agreement#An at-large official has no district tally worth drawing]]
  def at_large?
    district.number.zero?
  end

  # @lat: [[voter-privacy-threshold#Districts are sent as percentages only]]
  def for_percent
    rounded_percentages&.fetch(:for)
  end

  def against_percent
    rounded_percentages&.fetch(:against)
  end

  private

  def rounded_percentages
    return nil if comparison_suppressed?

    VoteComparisonPrivacy.rounded_percentages({for: self.for, against: against}, voters: self.for + against)
  end
end
