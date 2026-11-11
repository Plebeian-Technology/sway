require "rails_helper"

RSpec.describe ScoreChannel, type: :channel do
  include_context "Setup"

  let(:user) { setup.last }

  before do
    stub_connection(current_user: user)
  end

  describe "#subscribed" do
    it "confirms the subscription" do
      subscribe
      expect(subscription).to be_confirmed
    end

    it "streams from scores_<user_id>" do
      subscribe
      expect(subscription).to have_stream_from("scores_#{user.id}")
    end
  end

  describe "#unsubscribed" do
    it "does not raise when disconnecting" do
      subscribe
      expect { subscription.unsubscribe_from_channel }.not_to raise_error
    end
  end
end
