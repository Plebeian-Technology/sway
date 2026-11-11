# frozen_string_literal: true

require "rails_helper"

# @lat: [[legislation-pipeline#Runs, resume and restart]]
RSpec.describe ReclaimAbandonedPipelineRunsJob do
  # updated_at is written by every save, so a factory cannot produce the row
  # this job is about. update_all writes it without a callback pushing it back
  # to now.
  def abandoned_run(status: "summarizing", quiet_for: LegislationPipelineRun::ABANDONED_AFTER + 1.minute, **attrs)
    run = create(:legislation_pipeline_run, status: status, **attrs)
    LegislationPipelineRun.where(id: run.id).update_all(updated_at: quiet_for.ago)
    run.reload
  end

  before do
    allow(SwayLogging).to receive(:warn)
    allow(SwayLogging).to receive(:info)
    allow(PipelineActivityLogger).to receive(:emit_state_transition!)
    allow(PipelineRunChannel).to receive(:broadcast_to)
    # Its table is absent in test and the lookup fails closed, so an unstubbed
    # example would silently test the attended case.
    allow(LegislationPipelineRun).to receive(:solid_queue_job_exists_for?).and_return(false)
  end

  # THE CASE THAT HAD TO FAIL FIRST. `summarizing` is invisible to the orphan
  # scope, which only ever looks at queued and running, so nothing on a timer
  # could see this row at all.
  it "closes a run stopped inside a stage that nothing is carrying" do
    run = abandoned_run

    expect(described_class.new.perform).to eq(1)
    expect(run.reload.status).to eq("failed")
  end

  it "closes a run stopped in any other non-final status too" do
    LegislationPipelineRun::PHASE_52_NON_TERMINAL_STATES.each do |status|
      run = abandoned_run(status: status.to_s)

      described_class.new.perform

      expect(run.reload.status).to eq("failed"), "#{status} was left open"
    end
  end

  # The operator has to be able to answer "why does a run that was working now
  # say failed" from the run itself, without reading a log.
  it "records why, naming the stage it stopped in and when it went quiet" do
    run = abandoned_run(status: "fetching_hearings")
    quiet_since = run.updated_at

    described_class.new.perform

    # Dashed, as the Run pipeline control spells it — not the underscored name
    # the status column carries.
    expect(run.reload.error_message).to include("fetch-hearings", quiet_since.utc.iso8601, "Resume")
  end

  # Stamped by the same transition, so the run stops reading as one that never
  # ended.
  it "gives the closed run a finish time" do
    run = abandoned_run

    described_class.new.perform

    expect(run.reload.completed_at).to be_present
  end

  # A run inside a slow stage writes nothing to its own row for hours — per-bill
  # progress goes to pipeline_run_bills — so a live job is the only thing that
  # separates "slow" from "gone".
  it "leaves a quiet run alone while a job is still carrying it" do
    allow(LegislationPipelineRun).to receive(:solid_queue_job_exists_for?).and_return(true)
    run = abandoned_run

    expect(described_class.new.perform).to eq(0)
    expect(run.reload.status).to eq("summarizing")
  end

  it "leaves a run alone while something is still writing to it" do
    run = abandoned_run(quiet_for: 1.minute)

    expect(described_class.new.perform).to eq(0)
    expect(run.reload.status).to eq("summarizing")
  end

  it "leaves a finished run alone" do
    run = abandoned_run(status: "succeeded")

    expect(described_class.new.perform).to eq(0)
    expect(run.reload.status).to eq("succeeded")
  end

  # A worker writes in the gap between the candidate query and the write. The
  # lock's reload is what turns that write into a decision.
  it "spares a run that woke up after the candidate query" do
    run = abandoned_run
    allow_any_instance_of(LegislationPipelineRun).to receive(:with_lock).and_wrap_original do |original, locked, &block|
      LegislationPipelineRun.where(id: locked.id).update_all(updated_at: Time.current)
      original.call(&block)
    end

    expect(described_class.new.perform).to eq(0)
    expect(run.reload.status).to eq("summarizing")
  end

  # Oldest first, so the row that has been holding the Run button off longest is
  # the one a bounded sweep gets to.
  it "takes the longest-quiet runs first and leaves the rest for the next tick" do
    stub_const("#{described_class}::MAX_ROWS_PER_SWEEP", 1)
    older = abandoned_run(quiet_for: 3.days)
    newer = abandoned_run(quiet_for: 5.hours)

    expect(described_class.new.perform).to eq(1)
    expect(older.reload.status).to eq("failed")
    expect(newer.reload.status).to eq("summarizing")
  end

  # A raising row must not lead every tick and hide the rows behind it — the
  # sweep is oldest-first, which is exactly how that failure hides work.
  it "carries on past a run it cannot close, and says which one" do
    stuck = abandoned_run(quiet_for: 3.days)
    healthy = abandoned_run(quiet_for: 5.hours)
    allow(SwayLogging).to receive(:log_exception)
    # Raised from inside the transition, where a competing writer on a single Pi
    # would land, and where a raise really does roll the transition back.
    allow(PipelineActivityLogger).to receive(:emit_state_transition!) do |run:, **|
      raise ActiveRecord::StatementInvalid, "database is locked" if run.id == stuck.id
    end

    expect(described_class.new.perform).to eq(1)
    expect(healthy.reload.status).to eq("failed")
    expect(stuck.reload.status).to eq("summarizing")
    expect(SwayLogging).to have_received(:log_exception)
      .with("reclaim_abandoned_pipeline_runs.row_failed", hash_including(run_id: stuck.id))
  end
end
