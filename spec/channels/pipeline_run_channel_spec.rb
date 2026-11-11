require "rails_helper"

RSpec.describe PipelineRunChannel, type: :channel do
  include_context "Setup"

  let(:admin) { create(:user, :sway_admin) }
  let(:run_id) { "abc123" }

  before do
    stub_connection(current_user: admin)
  end

  describe "#subscribed" do
    it "confirms the subscription for an admin" do
      subscribe(run_id: run_id)
      expect(subscription).to be_confirmed
    end

    it "streams_for the run_id (not stream_from)" do
      subscribe(run_id: run_id)
      expect(subscription).to have_stream_from(PipelineRunChannel.broadcasting_for(run_id))
    end

    it "rejects non-admin users (ASVS V4)" do
      non_admin = create(:user, is_registration_complete: true)
      stub_connection(current_user: non_admin)
      subscribe(run_id: run_id)
      expect(subscription).to be_rejected
    end
  end

  describe "#unsubscribed" do
    it "does not raise when disconnecting" do
      subscribe(run_id: run_id)
      expect { subscription.unsubscribe_from_channel }.not_to raise_error
    end
  end
end
