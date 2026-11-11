class OnLegislatorVoteUpdateScoresJob < ApplicationJob
  queue_as :background

  # @lat: [[vote-triggered-score-jobs-design#Why OnLegislatorVoteUpdateScoresJob recomputes from scratch instead of applying deltas]]
  limits_concurrency to: 1, key: ->(legislator_id, _legislator_term_id = nil) { "scores_legislator_#{legislator_id}" }

  # @lat: [[vote-triggered-score-jobs-design#Why OnLegislatorVoteUpdateScoresJob recomputes from scratch instead of applying deltas]]
  def perform(legislator_id, legislator_term_id = nil)
    legislator = Legislator.find_by(id: legislator_id)
    return if legislator.nil? # the legislator was deleted, which cascaded to the vote

    legislator_term =
      (legislator_term_id && LegislatorTerm.find_by(id: legislator_term_id, legislator_id: legislator.id)) ||
      legislator.active_term
    return if legislator_term.nil?

    user_legislators_scope =
      if legislator_term == legislator.active_term
        UserLegislator.where(legislator_id: legislator.id, active: true)
      else
        UserLegislator.where(legislator_id: legislator.id).includes(:user)
      end

    ApplicationRecord.transaction(requires_new: true) do
      ScoreRecomputeService.recompute_legislator!(legislator_term)
      user_legislators_scope.find_each do |user_legislator|
        ScoreRecomputeService.recompute_user_legislator!(user_legislator, legislator_term)
      end
    end
  end
end
