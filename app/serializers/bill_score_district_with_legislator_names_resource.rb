# frozen_string_literal: true

# @lat: [[district-chart-tooltip#The mobile bill JSON carries the names, the web page does not]]
class BillScoreDistrictWithLegislatorNamesResource < BillScoreDistrictResource
  attribute :legislator_names do |district_score|
    params.fetch(:legislator_names_by_district_id).fetch(district_score.district_id, [])
  end
end
