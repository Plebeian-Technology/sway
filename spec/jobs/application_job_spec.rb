require "rails_helper"

RSpec.describe ApplicationJob, type: :job do
  include ActiveJob::TestHelper

  # @lat: [[application-job-discard-on-deserialization#Why ApplicationJob discards ActiveJob::DeserializationError]]
  describe "discard_on ActiveJob::DeserializationError" do
    it "discards a job whose record was destroyed before perform, without raising" do
      user_vote = create(:user_vote)
      # Queue the job under test by hand. The after_create_commit callback may
      # or may not fire inside a transactional test; either way, every queued
      # job now points at the vote that is about to be destroyed.
      OnUserVoteUpdateScoresJob.perform_later(user_vote)
      user_vote.destroy!

      expect { perform_enqueued_jobs }.not_to raise_error
      # Dropped rather than retried: nothing is left to run.
      expect(enqueued_jobs).to be_empty
    end
  end
end
