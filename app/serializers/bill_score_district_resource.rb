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
end
