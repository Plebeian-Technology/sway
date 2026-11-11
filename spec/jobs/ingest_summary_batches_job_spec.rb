# frozen_string_literal: true

require "rails_helper"

# @lat: [[explanation/llm-summaries#Batch summarisation#Why no job waits on a batch]]
RSpec.describe IngestSummaryBatchesJob do
  def awaiting_run(batch_id)
    run = create(:legislation_pipeline_run, status: "awaiting_summary_batch",
      current_stage: "summarize", started_at: 1.minute.ago)
    create(:pipeline_run_summary_batch, legislation_pipeline_run: run, batch_id: batch_id)
    run
  end

  before { allow(SummaryBatchIngest).to receive(:call) }

  it "sweeps a run holding a batch nothing has read back yet" do
    run = awaiting_run("msgbatch_sweep_1")

    described_class.new.perform

    expect(SummaryBatchIngest).to have_received(:call).with(run: run)
  end

  # @lat: [[explanation/llm-summaries#Batch summarisation#Which runs the sweep can reach]]
  it "sweeps a run parked awaiting a batch once every batch is ingested" do
    run = awaiting_run("msgbatch_sweep_2")
    run.pipeline_run_summary_batches.update_all(ingested_at: Time.current)

    described_class.new.perform

    expect(SummaryBatchIngest).to have_received(:call).with(run: run)
  end

  # @lat: [[explanation/llm-summaries#Batch summarisation#Which runs the sweep can reach]]
  it "sweeps a run that ended holding a batch nothing has read back" do
    run = create(:legislation_pipeline_run, :failed)
    create(:pipeline_run_summary_batch, legislation_pipeline_run: run, batch_id: "msgbatch_terminal")

    described_class.new.perform

    expect(SummaryBatchIngest).to have_received(:call).with(run: run)
  end

  # @lat: [[explanation/llm-summaries#Batch summarisation#Which runs the sweep can reach]]
  it "leaves a run whose own stage loop is still going alone" do
    run = create(:legislation_pipeline_run, status: "summarizing",
      current_stage: "summarize", started_at: 1.minute.ago)
    create(:pipeline_run_summary_batch, legislation_pipeline_run: run, batch_id: "msgbatch_mid_dag")

    described_class.new.perform

    expect(SummaryBatchIngest).not_to have_received(:call)
  end

  it "leaves a run that is not waiting on a batch alone" do
    create(:legislation_pipeline_run, :running)

    described_class.new.perform

    expect(SummaryBatchIngest).not_to have_received(:call)
  end

  it "carries on to the next run when one raises" do
    first = awaiting_run("msgbatch_sweep_3")
    second = awaiting_run("msgbatch_sweep_4")
    allow(SummaryBatchIngest).to receive(:call).with(run: first).and_raise(Llm::TransportError, "boom")
    allow(SwayLogging).to receive(:log_exception)

    described_class.new.perform

    expect(SummaryBatchIngest).to have_received(:call).with(run: second)
  end

  it "says which run it could not read, so a repeat every tick is visible" do
    first = awaiting_run("msgbatch_sweep_5")
    allow(SummaryBatchIngest).to receive(:call).and_raise(Llm::TransportError, "boom")
    allow(SwayLogging).to receive(:log_exception)

    described_class.new.perform

    expect(SwayLogging).to have_received(:log_exception).with(
      "ingest_summary_batches.run_failed", hash_including(run_id: first.id)
    )
  end

  it "reports how many runs it swept" do
    awaiting_run("msgbatch_sweep_6")
    awaiting_run("msgbatch_sweep_7")

    expect(described_class.new.perform).to eq(2)
  end

  it "sweeps no more runs than one tick allows" do
    stub_const("#{described_class}::MAX_RUNS_PER_SWEEP", 1)
    awaiting_run("msgbatch_sweep_8")
    awaiting_run("msgbatch_sweep_9")

    expect(described_class.new.perform).to eq(1)
  end

  it "takes the runs in id order, so what one tick left over leads the next" do
    awaiting_run("msgbatch_sweep_10")
    relation = LegislationPipelineRun.with_pending_summary_batches
    allow(LegislationPipelineRun).to receive(:with_pending_summary_batches).and_return(relation)
    allow(relation).to receive(:order).and_call_original

    described_class.new.perform

    expect(relation).to have_received(:order).with(:id)
  end

  it "runs on the background queue" do
    expect(described_class.new.queue_name).to eq("background")
  end

  # @lat: [[explanation/llm-summaries#Batch summarisation#A batch is read back exactly once]]
  describe "limits_concurrency declaration" do
    it "lets one sweep run at a time" do
      expect(described_class.new.concurrency_limit).to eq(1)
    end

    it "keys that limit across every run, not per run" do
      expect(described_class.new.concurrency_key)
        .to eq("IngestSummaryBatchesJob/ingest_summary_batches")
    end

    it "drops a second enqueue rather than queueing it behind the first" do
      expect(described_class.new.concurrency_on_conflict).to eq(:discard)
    end

    it "holds the lock for 30 minutes" do
      expect(described_class.new.concurrency_duration).to eq(30.minutes)
    end
  end
end
