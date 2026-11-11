# frozen_string_literal: true

require "rails_helper"

# @lat: [[solid-queue-orphan-lookup-test-methodology#Why a stand-in table, not the real Solid Queue database]]
RSpec.describe SolidQueueRetentionJob, type: :job do
  before do
    conn = ActiveRecord::Base.connection
    @created_jobs_table = !conn.table_exists?(:solid_queue_jobs)
    @created_failed_table = !conn.table_exists?(:solid_queue_failed_executions)

    if @created_jobs_table
      conn.create_table(:solid_queue_jobs) do |t|
        t.string :class_name, null: false
        t.string :queue_name, null: false
        t.datetime :finished_at
        t.datetime :created_at, null: false
        t.datetime :updated_at, null: false
      end
    end
    if @created_failed_table
      conn.create_table(:solid_queue_failed_executions) do |t|
        t.bigint :job_id, null: false
        t.text :error
        t.datetime :created_at, null: false
        t.datetime :updated_at, null: false
      end
    end

    # These inherit from ActiveRecord::Base rather than ApplicationRecord on
    # purpose: the throwaway models must not pick up the app's connection
    # routing or default scopes.
    # rubocop:disable Rails/ApplicationRecord
    job_model = Class.new(ActiveRecord::Base) do
      self.table_name = "solid_queue_jobs" # steep:ignore
    end
    failed_model = Class.new(ActiveRecord::Base) do
      self.table_name = "solid_queue_failed_executions" # steep:ignore
    end
    # rubocop:enable Rails/ApplicationRecord
    stub_const("SolidQueue::Job", job_model)
    stub_const("SolidQueue::FailedExecution", failed_model)
  end

  after do
    conn = ActiveRecord::Base.connection
    if @created_failed_table && conn.table_exists?(:solid_queue_failed_executions)
      conn.drop_table(:solid_queue_failed_executions)
    end
    if @created_jobs_table && conn.table_exists?(:solid_queue_jobs)
      conn.drop_table(:solid_queue_jobs)
    end
  end

  # Add a job row with a chosen finished_at. Rails does not manage that column
  # the way it manages created_at, so it can be set right on create.
  def create_job(finished_at:, class_name: "GenerateBillSummaryJob")
    SolidQueue::Job.create!(class_name: class_name, queue_name: "background", finished_at: finished_at)
  end

  # Add a FailedExecution and then push its created_at into the past. Rails sets
  # created_at to now on create, so update_all is the only way to age the row.
  def create_failed(job_id:, created_at:)
    fe = SolidQueue::FailedExecution.create!(job_id: job_id, error: "boom")
    SolidQueue::FailedExecution.where(id: fe.id).update_all(created_at: created_at)
    fe
  end

  describe "#perform — finished-job clear" do
    it "deletes finished jobs older than FINISHED_RETENTION_DAYS, keeps newer + unfinished" do
      create_job(finished_at: 8.days.ago)  # delete (stale finished)
      create_job(finished_at: 2.days.ago)  # keep (recent finished)
      create_job(finished_at: nil)         # keep (unfinished — running/failed)

      expect { described_class.new.perform }
        .to change { SolidQueue::Job.count }.from(3).to(2)
      expect(SolidQueue::Job.where.not(finished_at: nil).where("finished_at < ?", 7.days.ago).count).to eq(0)
    end

    it "sweeps more than one batch (BATCH_SIZE boundary) in a single perform" do
      stub_const("#{described_class}::BATCH_SIZE", 2)
      5.times { create_job(finished_at: 8.days.ago) }

      expect { described_class.new.perform }.to change { SolidQueue::Job.count }.from(5).to(0)
    end
  end

  describe "#perform — terminal-failure prune" do
    it "deletes failed jobs whose FailedExecution is older than FAILED_RETENTION_DAYS, with their FailedExecution rows" do
      stale_job = create_job(finished_at: nil)
      create_failed(job_id: stale_job.id, created_at: 31.days.ago) # delete both
      fresh_job = create_job(finished_at: nil)
      create_failed(job_id: fresh_job.id, created_at: 10.days.ago)  # keep both

      expect { described_class.new.perform }
        .to change { SolidQueue::Job.count }.from(2).to(1)
        .and change { SolidQueue::FailedExecution.count }.from(2).to(1)

      expect(SolidQueue::Job.exists?(stale_job.id)).to be(false)
      expect(SolidQueue::Job.exists?(fresh_job.id)).to be(true)
    end

    it "does not touch finished jobs via the failed-prune path" do
      # A job that finished within the last 7 days must survive even if an old
      # FailedExecution somehow points at it. The finished_at check keeps this
      # prune from overlapping with #clear_finished.
      finished = create_job(finished_at: 1.day.ago)
      create_failed(job_id: finished.id, created_at: 31.days.ago)

      described_class.new.perform

      expect(SolidQueue::Job.exists?(finished.id)).to be(true)
    end
  end

  describe "#perform — return value" do
    it "returns the total integer count of rows deleted (finished + failed)" do
      2.times { create_job(finished_at: 8.days.ago) }   # 2 finished pruned
      failed_job = create_job(finished_at: nil)
      create_failed(job_id: failed_job.id, created_at: 31.days.ago) # 1 failed pruned

      expect(described_class.new.perform).to eq(3)
    end
  end

  describe "constants" do
    it "encodes the retention windows" do
      expect(described_class::FINISHED_RETENTION_DAYS).to eq(7)
      expect(described_class::FAILED_RETENTION_DAYS).to eq(30)
      expect(described_class::BATCH_SIZE).to eq(500)
    end
  end
end
