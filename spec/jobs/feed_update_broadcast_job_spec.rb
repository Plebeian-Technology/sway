# frozen_string_literal: true

require "rails_helper"

RSpec.describe FeedUpdateBroadcastJob, type: :job do
  describe "#perform" do
    it "calls FeedBroadcaster.notify with the distinct user ids" do
      allow(FeedBroadcaster).to receive(:notify)

      described_class.new.perform([11, 12, 11])

      expect(FeedBroadcaster).to have_received(:notify).with([11, 12])
    end

    it "does not call FeedBroadcaster.notify when user_ids is empty" do
      allow(FeedBroadcaster).to receive(:notify)

      described_class.new.perform([])

      expect(FeedBroadcaster).not_to have_received(:notify)
    end
  end
end
