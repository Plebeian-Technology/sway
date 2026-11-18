# frozen_string_literal: true

# @lat: [[scores-and-agreement#Scores and agreement#The five score families]]
class BillScoreDistrictResource < ApplicationResource
  attributes :bill_score_id

  attribute :district do |district_score|
    BillPageDistrictResource.new(district_score.district).serializable_hash
  end

  attribute :for do |district_score|
    district_score.for
  end

  attributes :against

  attribute :comparison_suppressed do |district_score|
    VoteComparisonPrivacy.suppressed?(district_score.for, district_score.against)
  end

  attribute :for_percent do |district_score|
    district_score.for_percent
  end

  attribute :against_percent do |district_score|
    district_score.against_percent
  end

  attribute :at_large do |district_score|
    district_score.at_large?
  end
end
