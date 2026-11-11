require "rails_helper"

RSpec.describe "UserVotes", type: :request do
  include_context "Setup"

  let(:sway_and_user) { setup }
  let(:sway_locale) { sway_and_user.first }
  let(:user) { sway_and_user.last }
  let(:bill) { create(:bill, sway_locale: sway_locale) }

  before { sign_in(user) }

  describe "POST /user_votes" do
    # @lat: [[user-votes-controller-notes#Why request specs POST support values in capitals]]

    it "creates a UserVote with support=FOR and redirects" do
      expect {
        post user_votes_path, params: {bill_id: bill.id, support: "FOR"}
      }.to change(UserVote, :count).by(1)
      expect(response).to have_http_status(:redirect)
    end

    it "creates a UserVote with support=AGAINST" do
      expect {
        post user_votes_path, params: {bill_id: bill.id, support: "AGAINST"}
      }.to change(UserVote, :count).by(1)
    end

    it "rejects voting on an inactive bill with 422 Unprocessable Content on mobile JSON" do
      inactive_bill = create(:bill, :without_session, sway_locale: sway_locale, active: false)

      expect {
        post user_votes_path, params: {bill_id: inactive_bill.id, support: "FOR"}, as: :json
      }.not_to change(UserVote, :count)

      expect(response).to have_http_status(:unprocessable_content)
      expect(json_body[:error][:code]).to eq("bill_inactive")
      expect(json_body[:error][:message]).to eq("Voting is closed for this bill.")
    end

    it "redirects to bill_path with flash[:alert] when voting on an inactive bill on web" do
      inactive_bill = create(:bill, :without_session, sway_locale: sway_locale, active: false)

      expect {
        post user_votes_path, params: {bill_id: inactive_bill.id, support: "FOR"}
      }.not_to change(UserVote, :count)

      expect(response).to redirect_to(bill_path(inactive_bill.id))
      expect(flash[:alert]).to eq("Voting is closed for this bill.")
    end

    it "redirects when signed out (authenticate_sway_user! gate)" do
      sign_out(user)
      post user_votes_path, params: {bill_id: bill.id, support: "FOR"}
      expect(response).to have_http_status(:unauthorized).or have_http_status(:redirect)
      expect(UserVote.count).to eq(0)
    end

    # @lat: [[user-votes-controller-notes#The regression this guards against]]
    describe "vote finality" do
      # On the web, voting again with a different support is refused. The row
      # count holds, the stored support stays FOR, and the redirect carries an
      # alert flash so VotePanel's onError undoes the vote it had already
      # shown.
      it "rejects a different-support re-vote and keeps the original support (web)" do
        post user_votes_path, params: {bill_id: bill.id, support: "FOR"}

        expect {
          post user_votes_path, params: {bill_id: bill.id, support: "AGAINST"}
        }.not_to change(UserVote, :count)

        expect(UserVote.last&.support).to eq("FOR")
        expect(response).to have_http_status(:redirect)
        follow_redirect!
        expect(inertia).to have_flash(
          alert: "Your vote on this bill was already recorded and cannot be changed."
        )
      end

      # @lat: [[user-votes-controller-notes#Why a cast vote can never be changed]]
      it "does not adjust aggregates on a rejected re-vote" do
        post user_votes_path, params: {bill_id: bill.id, support: "FOR"}
        score = BillScore.find_or_create_by!(bill: bill)
        score.update_columns(for: 1, against: 0)

        post user_votes_path, params: {bill_id: bill.id, support: "AGAINST"}

        score.reload
        expect(score.read_attribute("for")).to eq(1)
        expect(score.read_attribute("against")).to eq(0)
      end

      # On mobile the same refusal comes back as the standard error envelope.
      it "rejects a different-support re-vote with a 422 error envelope (mobile)" do
        post user_votes_path, params: {bill_id: bill.id, support: "FOR"}, as: :json

        post user_votes_path, params: {bill_id: bill.id, support: "AGAINST"}, as: :json

        expect(response).to have_http_status(:unprocessable_content)
        expect(json_body[:error][:code]).to eq("vote_already_recorded")
        expect(UserVote.last&.support).to eq("FOR")
      end

      # Posting again with the SAME support succeeds and changes nothing: no new
      # row, and the "Vote saved!" notice still appears.
      it "treats a same-support re-POST as idempotent success" do
        post user_votes_path, params: {bill_id: bill.id, support: "FOR"}
        expect(response).to have_http_status(:redirect)

        expect {
          post user_votes_path, params: {bill_id: bill.id, support: "FOR"}
        }.not_to change(UserVote, :count)

        expect(response).to have_http_status(:redirect)
        follow_redirect!
        expect(inertia).to have_flash(notice: "Vote saved!")
      end

      # @lat: [[user-votes-controller-notes#Why create rescues RecordNotUnique]]
      it "treats a RecordNotUnique race as an already-recorded vote (no 500)" do
        UserVote.create!(user: user, bill: bill, support: "FOR")
        # Act out the race: the first find_by returns nil, the INSERT loses to
        # the unique index, and the rescue's second find_by returns the row
        # that won.
        call_count = 0
        allow(UserVote).to receive(:find_by).and_wrap_original do |original, conditions|
          call_count += 1
          (call_count == 1) ? nil : original.call(conditions)
        end
        allow_any_instance_of(UserVote).to receive(:save).and_raise(ActiveRecord::RecordNotUnique)

        post user_votes_path, params: {bill_id: bill.id, support: "AGAINST"}

        expect(response).to have_http_status(:redirect)
        expect(UserVote.count).to eq(1)
        expect(UserVote.first&.support).to eq("FOR")
      end
    end

    # @lat: [[flash-notice-survives-redirect-to-toast#Why success flash notices are pinned across a redirect]]
    it "surfaces a 'Vote saved!' flash notice on the followed redirect" do
      post user_votes_path, params: {bill_id: bill.id, support: "FOR"}
      follow_redirect!

      expect(inertia).to have_flash(notice: "Vote saved!")
    end

    # A redirect_to pointing at another site must be defused. On the web the
    # raw value trips Rails' raise_on_open_redirects and 500s; on mobile it used
    # to be copied straight into the JSON response. url_from returns nil for
    # anything off-site, so both fall back to the bill path.
    it "ignores an off-site redirect_to and falls back to the bill path (web)" do
      post user_votes_path,
        params: {bill_id: bill.id, support: "FOR", redirect_to: "https://evil.example/x"}

      expect(response).to redirect_to(bill_path(bill.id))
    end

    it "sanitizes an off-site redirect_to in the mobile JSON envelope" do
      post user_votes_path,
        params: {bill_id: bill.id, support: "FOR", redirect_to: "https://evil.example/x"},
        as: :json

      expect(response).to have_http_status(:ok)
      expect(json_body[:redirect]).to eq(bill_path(bill.id))
    end
  end
end
