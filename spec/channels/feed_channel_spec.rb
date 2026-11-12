# frozen_string_literal: true

require "rails_helper"

RSpec.describe FeedChannel, type: :channel do
  include_context "Setup"

  describe "#subscribed" do
    it "confirms subscription and streams from feed_<user_id> when authenticated" do
      user = setup.last
      stub_connection(current_user: user)

      subscribe

      expect(subscription).to be_confirmed
      expect(subscription).to have_stream_from("feed_#{user.id}")
    end

    it "rejects subscription when current_user is nil" do
      stub_connection(current_user: nil)

      subscribe

      expect(subscription).to be_rejected
    end
  end

  describe "#unsubscribed" do
    it "does not raise when disconnecting" do
      user = setup.last
      stub_connection(current_user: user)
      subscribe

      expect { subscription.unsubscribe_from_channel }.not_to raise_error
    end
  end
end
