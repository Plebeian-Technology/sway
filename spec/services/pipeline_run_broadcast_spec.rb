# frozen_string_literal: true

require "rails_helper"

# @lat: [[legislation-pipeline#Runs, resume and restart#A broadcast that fails must not fail the run]]
RSpec.describe PipelineRunBroadcast do
  describe ".deliver" do
    it "sends the payload to the stream" do
      expect(PipelineRunChannel).to receive(:broadcast_to).with("run-42", scope: "run", status: "running")

      result = described_class.deliver(
        "run-42",
        {scope: "run", status: "running"},
        log_event: "spec.broadcast"
      )

      expect(result).to be(true)
    end

    it "swallows a failure to send and says so in the answer" do
      allow(PipelineRunChannel).to receive(:broadcast_to).and_raise(IOError, "the message bus is down")
      allow(SwayLogging).to receive(:log_exception)
      allow(Sentry).to receive(:capture_exception)

      result = nil
      expect {
        result = described_class.deliver("run-42", {scope: "run"}, log_event: "spec.broadcast")
      }.not_to raise_error

      expect(result).to be(false)
    end

    it "logs the failure under the caller's own name, with its context" do
      allow(PipelineRunChannel).to receive(:broadcast_to).and_raise(IOError, "the message bus is down")
      allow(Sentry).to receive(:capture_exception)

      expect(SwayLogging).to receive(:log_exception).with(
        "spec.broadcast",
        hash_including(level: :warn, stream_id: "run-42", run_id: 7)
      )

      described_class.deliver("run-42", {scope: "run"}, log_event: "spec.broadcast", run_id: 7)
    end

    # log_exception reaches Rails.logger and nothing else, so without reporting
    # a bus down for a week looks like a quiet week.
    it "reports the failure, because the log alone reaches nobody" do
      error = IOError.new("the message bus is down")
      allow(PipelineRunChannel).to receive(:broadcast_to).and_raise(error)
      allow(SwayLogging).to receive(:log_exception)

      expect(Sentry).to receive(:capture_exception).with(
        error,
        hash_including(extra: hash_including(log_event: "spec.broadcast", stream_id: "run-42", run_id: 7))
      )

      described_class.deliver("run-42", {scope: "run"}, log_event: "spec.broadcast", run_id: 7)
    end
  end

  # These drive the REAL callers, because a correct helper proves nothing about
  # whether the callers go through it — which was the defect.
  describe "the senders that used to take the caller down with them" do
    it "lets a run change status even when the send fails" do
      run = create(:legislation_pipeline_run, status: "queued")
      allow(PipelineRunChannel).to receive(:broadcast_to).and_raise(IOError, "the message bus is down")
      allow(SwayLogging).to receive(:log_exception)
      allow(Sentry).to receive(:capture_exception)

      expect { run.update!(status: "running") }.not_to raise_error
      expect(run.reload.status).to eq("running")
    end

    it "lets a bill inside a run change status even when the send fails" do
      run = create(:legislation_pipeline_run)
      bill_run = create(:pipeline_run_bill, legislation_pipeline_run: run, status: "pending")
      allow(PipelineRunChannel).to receive(:broadcast_to).and_raise(IOError, "the message bus is down")
      allow(SwayLogging).to receive(:log_exception)
      allow(Sentry).to receive(:capture_exception)

      expect { bill_run.update!(status: "running") }.not_to raise_error
      expect(bill_run.reload.status).to eq("running")
    end
  end
end
