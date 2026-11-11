# frozen_string_literal: true

require "rails_helper"

# @lat: [[legislation-pipeline-run-orphan-detection#The Solid Queue job lookup]]
RSpec.describe PipelineRunsController, "#solid_queue_job_exists_for?", type: :request do
  # @lat: [[solid-queue-orphan-lookup-test-methodology#Why a stand-in table, not the real Solid Queue database]]
  before(:all) do
    expect(PipelineRunsController.private_instance_methods(false))
      .to include(:solid_queue_job_exists_for?),
        "PipelineRunsController#solid_queue_job_exists_for? was renamed " \
        "or removed. Every controller.send(:solid_queue_job_exists_for?, ...) " \
        "call below would raise NoMethodError. Update the spec to the new " \
        "method name (and update the production-shape contract upstream)."
  end

  before do
    conn = ActiveRecord::Base.connection
    @created_solid_queue_jobs_table = !conn.table_exists?(:solid_queue_jobs)
    if @created_solid_queue_jobs_table
      conn.create_table(:solid_queue_jobs) do |t|
        t.string :active_job_id
        t.text :arguments
        t.string :class_name, null: false
        t.string :concurrency_key
        t.string :queue_name, null: false
        t.integer :priority, default: 0, null: false
        t.datetime :scheduled_at
        t.datetime :finished_at
        t.datetime :created_at, null: false
        t.datetime :updated_at, null: false
      end
    end

    test_job_model = Class.new(ApplicationRecord) do
      # An anonymous ActiveRecord subclass; the type checker reads the Class.new body as Object.
      self.table_name = "solid_queue_jobs" # steep:ignore
    end
    stub_const("SolidQueue::Job", test_job_model)
  end

  after do
    # Drop the table only if THIS spec created it. A table left behind by
    # another spec — or one a future test setup creates on the main connection
    # for Solid Queue — is left alone, so later specs do not find it suddenly
    # missing.
    conn = ActiveRecord::Base.connection
    if @created_solid_queue_jobs_table && conn.table_exists?(:solid_queue_jobs)
      conn.drop_table(:solid_queue_jobs)
    end
  end

  let(:bill) { create(:bill) }
  let(:run) { create(:legislation_pipeline_run, bill: bill, status: "running") }
  let(:other_run) { create(:legislation_pipeline_run, bill: bill, status: "running") }

  # @lat: [[solid-queue-orphan-lookup-test-methodology#Why the serialized job arguments are spelled out by hand]]
  def serialized_active_job_arguments(run_id, origin: "fresh")
    # @type var exception_executions: Hash[String, Integer]
    exception_executions = {}
    {
      job_class: "RunLegislationPipelineJob",
      job_id: SecureRandom.uuid,
      provider_job_id: nil,
      queue_name: "background",
      priority: nil,
      arguments: [
        run_id,
        {"_aj_ruby2_keywords" => ["origin"], "origin" => origin}
      ],
      executions: 0,
      exception_executions: exception_executions,
      locale: "en",
      timezone: "UTC",
      enqueued_at: Time.current.iso8601(9)
    }.to_json
  end

  def insert_solid_queue_job(run_id:, finished_at: nil, class_name: "RunLegislationPipelineJob")
    SolidQueue::Job.create!(
      class_name: class_name,
      arguments: serialized_active_job_arguments(run_id),
      queue_name: "background",
      finished_at: finished_at,
      active_job_id: SecureRandom.uuid
    )
  end

  describe "anchored json_extract match" do
    it "returns true when an unfinished SolidQueue::Job has $.arguments[0] == run.id" do
      insert_solid_queue_job(run_id: run.id)
      controller = PipelineRunsController.new
      expect(controller.send(:solid_queue_job_exists_for?, run)).to be(true)
    end

    it "returns false for a different run_id (no substring false-positive on shared digits)" do
      # The old LIKE '%5%' query matched a job carrying run_id 50 when asked
      # about run id 5. Reading the exact JSON position must not.
      digit_overlap_run_id = run.id * 10
      insert_solid_queue_job(run_id: digit_overlap_run_id)
      controller = PipelineRunsController.new
      expect(controller.send(:solid_queue_job_exists_for?, run)).to be(false)
    end

    it "returns false when no SolidQueue::Job exists for any run" do
      controller = PipelineRunsController.new
      expect(controller.send(:solid_queue_job_exists_for?, run)).to be(false)
    end

    it "ignores jobs of a different class_name even with matching $.arguments[0]" do
      SolidQueue::Job.create!(
        class_name: "SomeOtherJob",
        arguments: serialized_active_job_arguments(run.id),
        queue_name: "background",
        finished_at: nil,
        active_job_id: SecureRandom.uuid
      )
      controller = PipelineRunsController.new
      expect(controller.send(:solid_queue_job_exists_for?, run)).to be(false)
    end
  end

  describe "finished_at filter (second half of cycle-7 HIGH-2 fix)" do
    it "returns false when the matching job has a non-null finished_at" do
      insert_solid_queue_job(run_id: run.id, finished_at: 1.hour.ago)
      controller = PipelineRunsController.new
      expect(controller.send(:solid_queue_job_exists_for?, run)).to be(false)
    end

    it "still returns true when a *separate* unfinished match exists alongside a finished one" do
      insert_solid_queue_job(run_id: run.id, finished_at: 1.hour.ago)
      insert_solid_queue_job(run_id: run.id, finished_at: nil)
      controller = PipelineRunsController.new
      expect(controller.send(:solid_queue_job_exists_for?, run)).to be(true)
    end
  end

  describe "fail-closed behaviour" do
    it "returns true (refuses orphan-delete) when the underlying query raises" do
      # Swap the test model again so .where raises, standing in for a missing
      # table or malformed JSON in production.
      raising_model = Class.new do
        # An anonymous Class.new; the type checker cannot name its singleton.
        def self.where(*) # steep:ignore
          raise StandardError, "table missing"
        end
      end
      stub_const("SolidQueue::Job", raising_model)
      controller = PipelineRunsController.new
      expect(controller.send(:solid_queue_job_exists_for?, run)).to be(true)
    end
  end
end
