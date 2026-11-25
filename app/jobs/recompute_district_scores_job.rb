# frozen_string_literal: true

# @lat: [[score-updater-service-design#Why each score family uses a different scope and a different term]]
class RecomputeDistrictScoresJob < ApplicationJob
  queue_as :background

  def perform(bill_ids, legislator_ids)
    legislators = Legislator.where(id: legislator_ids).to_a
    ScoreRecomputeService.recompute_district_scores!(bill_ids, legislators:)
  end
end
