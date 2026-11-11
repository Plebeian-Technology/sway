# frozen_string_literal: true

require "rails_helper"
require "tmpdir"

RSpec.describe RunLegislationPipelineJob, "queue ownership" do
  describe "operator stops" do
    before do
      allow(PipelineRunChannel).to receive(:broadcast_to)
    end

    # @lat: [[legislation-pipeline#Runs, resume and restart#Queue ownership outlives an operator stop]]
    it "does no work when a stopped or finished run is redelivered" do
      LegislationPipelineRun::TERMINAL_STATUSES.each do |status|
        run = create(:legislation_pipeline_run, status: status.to_s)
        job = described_class.new
        expect(job).not_to receive(:pre_seed_single_bill_pipeline_run_bill!)
        expect(job).not_to receive(:hydrate_pipeline_run_bills_from_disk!)
        expect(FetchBillsService).not_to receive(:new)

        expect { job.perform(run.id) }.not_to change { run.reload.updated_at }
        expect(run.reload.status).to eq(status.to_s)
      end
    end

    it "stops after a run-level service when an operator failed the run during that service" do
      run = create(:legislation_pipeline_run, stages: %w[fetch-law extract-text], download_missing_assets: false)
      job = described_class.new
      allow(job).to receive(:pre_seed_single_bill_pipeline_run_bill!)
      allow(job).to receive(:hydrate_pipeline_run_bills_from_disk!)
      service = instance_double(FetchLawService)
      allow(FetchLawService).to receive(:new).and_return(service)
      allow(service).to receive(:call) do
        run.reload.update!(error_message: "Force-failed by operator")
        run.force_fail!
      end
      expect(job).not_to receive(:run_bill_level_stage)
      expect(job).not_to receive(:handle_run_failure)

      expect { job.perform(run.id) }.not_to raise_error

      expect(run.reload.status).to eq("failed")
      expect(run.error_message).to eq("Force-failed by operator")
      expect(run.pipeline_run_stages.find_by!(stage_name: "fetch_law").status).to eq("failed")
    end

    it "checks a stop before entering the first run-level service" do
      run = create(:legislation_pipeline_run, stages: ["fetch-law"], download_missing_assets: false)
      job = described_class.new
      allow(job).to receive(:pre_seed_single_bill_pipeline_run_bill!)
      allow(job).to receive(:hydrate_pipeline_run_bills_from_disk!) { run.reload.mark_cancelled! }
      expect(FetchLawService).not_to receive(:new)

      expect { job.perform(run.id) }.not_to raise_error
      expect(run.reload.status).to eq("cancelled")
    end
  end

  describe "Solid Queue contention" do
    self.use_transactional_tests = false

    it "unblocks the waiting job when a redelivered stopped run exits" do
      stopped_run = build(:legislation_pipeline_run, id: 11, status: "failed")
      allow(LegislationPipelineRun).to receive(:find_by).with(id: 11).and_return(stopped_run)
      Dir.mktmpdir("pipeline-queue-spec") do |dir|
        config = ActiveRecord::DatabaseConfigurations::HashConfig.new(
          Rails.env, "queue_spec", {adapter: "sqlite3", database: File.join(dir, "queue.sqlite3")}
        )
        ActiveRecord::Tasks::DatabaseTasks.with_temporary_connection(config) do
          ActiveRecord::Tasks::DatabaseTasks.load_schema(config, :ruby, Rails.root.join("db", "queue_schema.rb").to_s)
          worker = SolidQueue::Process.create!(kind: "Worker", name: "pipeline-queue-spec", pid: Process.pid, last_heartbeat_at: Time.current)
          first = SolidQueue::Job.enqueue(described_class.new(11))
          claim = SolidQueue::ReadyExecution.claim(["background"], 1, worker.id).fetch(0)
          second = SolidQueue::Job.enqueue(described_class.new(12))

          expect(first.reload.claimed_execution).to be_present
          expect(second.reload.blocked_execution).to be_present
          expect(second.ready_execution).to be_nil
          expect(second.concurrency_key).to eq("RunLegislationPipelineJob/legislation_pipeline_global")

          claim.perform

          expect(first.reload.claimed_execution).to be_nil
          expect(second.reload.ready_execution).to be_present
          expect(second.blocked_execution).to be_nil
        end
      end
    end
  end
end
