# frozen_string_literal: true

require "rails_helper"

# @lat: [[explanation/llm-summaries#Batch summarisation#One finalizer for the job and the ingest]]
RSpec.describe PipelineRunFinalizer do
  let(:run) { create(:legislation_pipeline_run, :running) }

  def bill_run_with(stage_status)
    create(:pipeline_run_bill, legislation_pipeline_run: run,
      stage_results: {"summarize" => {"status" => stage_status, "at" => Time.current.iso8601}})
  end

  it "lands a run whose bills all succeeded in :succeeded" do
    bill_run_with("succeeded")

    described_class.call(run: run)

    expect(run.reload.status).to eq("succeeded")
  end

  it "lands a run with a failed bill in :partial" do
    bill_run_with("succeeded")
    bill_run_with("failed")

    described_class.call(run: run)

    expect(run.reload.status).to eq("partial")
  end

  it "reports bills nothing ran for, which reach no other record" do
    bill_run_with("not_run")
    allow(SwayLogging).to receive(:warn)

    described_class.call(run: run)

    expect(SwayLogging).to have_received(:warn).with(
      "run_legislation_pipeline.bills_not_run", hash_including(not_run_bills: 1)
    )
  end

  it "carries the origin it was given into that report" do
    bill_run_with("not_run")
    allow(SwayLogging).to receive(:warn)

    described_class.call(run: run, origin: "resume")

    expect(SwayLogging).to have_received(:warn).with(
      "run_legislation_pipeline.bills_not_run", hash_including(origin: "resume")
    )
  end

  it "force-fails a run left in a non-terminal state it cannot succeed from" do
    stuck = create(:legislation_pipeline_run, status: "summarizing", current_stage: "summarize")
    allow(SwayLogging).to receive(:error)

    described_class.call(run: stuck)

    expect(stuck.reload.status).to eq("failed")
  end

  it "records why a stuck run was force-failed" do
    stuck = create(:legislation_pipeline_run, status: "summarizing", current_stage: "summarize")
    allow(SwayLogging).to receive(:error)

    described_class.call(run: stuck)

    expect(stuck.reload.error_message).to include("non_terminal_at_finalize")
  end

  it "leaves a run that is already terminal alone" do
    done = create(:legislation_pipeline_run, :completed)

    expect { described_class.call(run: done) }.not_to change { done.reload.status }
  end
end
