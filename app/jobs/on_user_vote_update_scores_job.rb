class OnUserVoteUpdateScoresJob < ApplicationJob
  queue_as :background

  def perform(user_vote)
    Rails.logger.info("OnUserVoteUpdateScoresJob.perform")
    ScoreUpdaterService.new(user_vote).run
  end
end
