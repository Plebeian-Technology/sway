# frozen_string_literal: true

# @lat: [[scores-and-agreement#Scores and agreement#The five score families]]
class BillScoreResource < ApplicationResource
  attributes :id, :bill_id

  # @lat: [[voter-privacy-threshold#No endpoint sends a count that could identify a voter]]
  attribute :for do |score|
    score.visible_for
  end

  attribute :against do |score|
    score.visible_against
  end

  attribute :comparison_suppressed do |score|
    score.comparison_suppressed?
  end

  attributes :voters_needed

  attribute :districts do |score|
    district_scores = score.bill_score_districts.select(&:publishable?)
    # @lat: [[district-chart-tooltip#The mobile bill JSON carries the names, the web page does not]]
    if params[:district_legislator_names]
      names_by_district_id = legislator_names_by_district_id(district_scores)
      district_scores.map do |district_score|
        BillScoreDistrictWithLegislatorNamesResource
          .new(district_score, params: {legislator_names_by_district_id: names_by_district_id})
          .serializable_hash
      end
    else
      district_scores.map { |district_score| BillScoreDistrictResource.new(district_score).serializable_hash }
    end
  end

  private

  def legislator_names_by_district_id(district_scores)
    LegislatorTerm.current
      .where(district_id: district_scores.map(&:district_id))
      .includes(:legislator)
      .group_by(&:district_id)
      .transform_values { |terms| terms.map(&:legislator).uniq.map(&:full_name).sort_by(&:downcase) }
  end
end
