# frozen_string_literal: true

require "rails_helper"

RSpec.describe FeedUpdateBroadcastJob, type: :job do
  describe "#perform" do
    it "calls FeedBroadcaster.notify with the matching users" do
      user_a = create(:user)
      user_b = create(:user)
      other_user = create(:user)

      allow(FeedBroadcaster).to receive(:notify)

      described_class.new.perform([user_a.id, user_b.id, user_a.id])

      expect(FeedBroadcaster).to have_received(:notify) do |users|
        expect(users.to_a).to contain_exactly(user_a, user_b)
        expect(users.to_a).not_to include(other_user)
      end
    end

    it "does not call FeedBroadcaster.notify when user_ids is empty" do
      allow(FeedBroadcaster).to receive(:notify)

      described_class.new.perform([])

      expect(FeedBroadcaster).not_to have_received(:notify)
    end
  end
end
