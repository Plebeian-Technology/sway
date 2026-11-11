require "rails_helper"

RSpec.describe OnUserVoteUpdateScoresJob, type: :job do
  include ActiveJob::TestHelper

  include_context "Setup"

  describe "#perform" do
    it "enqueues the job with a user_vote" do
      sway_locale, user = setup
      legislator = create(:legislator)
      bill = create(:bill, sway_locale: sway_locale, legislator: legislator)
      user_vote = create(:user_vote, user: user, bill: bill)

      expect {
        described_class.perform_later(user_vote)
      }.to have_enqueued_job(described_class).with(user_vote)
    end

    # @lat: [[bill-session-archiving-tests#Bill session archive tests#Queued scores skip archives]]
    it "stands down when its vote's bill has since been archived" do
      sway_locale, user = setup
      bill = create(:bill, sway_locale: sway_locale)
      vote = create(:user_vote, user: user, bill: bill)
      bill.update!(archived_at: Time.current)
      allow(ScoreRecomputeService).to receive(:recompute_bill!)

      described_class.new.perform(vote)

      expect(ScoreRecomputeService).not_to have_received(:recompute_bill!)
      expect(UserVote.exists?(vote.id)).to eq(true)
    end

    # @lat: [[vote-triggered-score-jobs-design#Why the recompute spec writes a deliberately wrong tally first]]
    it "recomputes the bill's aggregate BillScore from the user vote" do
      sway_locale, user = setup
      legislator = create(:legislator)
      bill = create(:bill, sway_locale: sway_locale, legislator: legislator)
      user_vote = create(:user_vote, user: user, bill: bill)

      score = BillScore.find_or_create_by!(bill: bill)
      score.update_columns(for: 99, against: 99)

      described_class.new.perform(user_vote)

      score.reload
      expect(score.read_attribute("for")).to eq(1)
      expect(score.read_attribute("against")).to eq(0)
    end

    it "broadcasts refresh_scores to the user's ScoreChannel stream" do
      sway_locale, user = setup
      legislator = create(:legislator)
      bill = create(:bill, sway_locale: sway_locale, legislator: legislator)
      user_vote = create(:user_vote, user: user, bill: bill)

      expect {
        described_class.new.perform(user_vote)
      }.to have_broadcasted_to("scores_#{user.id}")
    end
  end
end
