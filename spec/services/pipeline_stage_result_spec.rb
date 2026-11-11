# frozen_string_literal: true

require "rails_helper"

# @lat: [[explanation/llm-summaries#Batch summarisation#One stage-result writer for the job and the ingest]]
RSpec.describe PipelineStageResult do
  let(:run) { create(:legislation_pipeline_run) }
  let(:bill_run) { create(:pipeline_run_bill, legislation_pipeline_run: run) }

  it "writes the status and a timestamp under the stage's key" do
    described_class.record(bill_run: bill_run, stage: :extract_text, status: "succeeded")

    entry = bill_run.reload.stage_results.fetch("extract_text")
    expect(entry.keys).to contain_exactly("status", "at")
    expect(entry["status"]).to eq("succeeded")
  end

  it "writes an error only when one is given" do
    described_class.record(bill_run: bill_run, stage: :summarize, status: "failed", error: "boom")

    expect(bill_run.reload.stage_results.dig("summarize", "error")).to eq("boom")
  end

  it "writes a reason only when one is given" do
    described_class.record(bill_run: bill_run, stage: :summarize, status: "skipped", reason: "no_model_call_made")

    expect(bill_run.reload.stage_results.dig("summarize", "reason")).to eq("no_model_call_made")
  end

  it "merges into the stages already there rather than replacing them" do
    described_class.record(bill_run: bill_run, stage: :extract_text, status: "succeeded")
    described_class.record(bill_run: bill_run, stage: :summarize, status: "awaiting_batch")

    expect(bill_run.reload.stage_results.keys).to contain_exactly("extract_text", "summarize")
  end

  it "refuses a stage the DAG does not name" do
    expect {
      described_class.record(bill_run: bill_run, stage: :not_a_stage, status: "succeeded")
    }.to raise_error(ArgumentError, /not in DAG_ORDER/)
  end

  it "writes what the job's own delegation writes" do
    other = create(:pipeline_run_bill, legislation_pipeline_run: run)
    RunLegislationPipelineJob.new.send(:record_stage_result, other, :summarize, "succeeded")
    described_class.record(bill_run: bill_run, stage: :summarize, status: "succeeded")

    expect(bill_run.reload.stage_results.dig("summarize", "status"))
      .to eq(other.reload.stage_results.dig("summarize", "status"))
  end
end
