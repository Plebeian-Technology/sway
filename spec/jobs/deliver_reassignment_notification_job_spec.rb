# frozen_string_literal: true

require "rails_helper"

RSpec.describe DeliverReassignmentNotificationJob, type: :job do
  let(:user) { create(:user) }

  describe "#perform" do
    it "invokes ReassignmentNotificationDispatchService" do
      dispatch_double = instance_double(ReassignmentNotificationDispatchService)
      allow(ReassignmentNotificationDispatchService).to receive(:new).and_return(dispatch_double)
      expect(dispatch_double).to receive(:call).with(user.id)

      described_class.perform_now(user.id)
    end

    it "is queued on the default queue" do
      expect(described_class.new.queue_name).to eq("default")
    end
  end
end
