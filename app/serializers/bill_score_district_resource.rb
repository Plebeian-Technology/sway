# frozen_string_literal: true

# @lat: [[voter-privacy-threshold#No endpoint sends a count that could identify a voter]]
class BillScoreDistrictResource < ApplicationResource
  attributes :bill_score_id

  attribute :district do |district_score|
    BillPageDistrictResource.new(district_score.district).serializable_hash
  end

  attribute :comparison_suppressed do |district_score|
    district_score.comparison_suppressed?
  end

  attributes :for_percent, :against_percent

  attribute :at_large do |district_score|
    district_score.at_large?
  end
end
