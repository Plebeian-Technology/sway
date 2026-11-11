# frozen_string_literal: true

require "rails_helper"

# @lat: [[legislation-pipeline#The legislation pipeline#Runs, resume and restart#The admin surface is index-only]]
RSpec.describe "PipelineRunsOrphanBulkDelete", type: :request do
  include_context "SessionDouble"

  include_examples "requires sway admin",
    verb: :delete,
    path: "/pipeline_runs/orphans"

  context "as admin" do
    let(:admin) { create(:user, :sway_admin) }

    before { session_hash[:user_id] = admin.id }

    # By default there are no live background jobs, which is what a row looks
    # like after the worker crashed and left it unattended.
    before do
      allow(LegislationPipelineRun).to receive(:solid_queue_job_exists_for?).and_return(false)
    end

    it "deletes every orphan-eligible row in one request" do
      orphan_a = create(:legislation_pipeline_run, status: "running", created_at: 5.hours.ago)
      orphan_b = create(:legislation_pipeline_run, status: "queued", created_at: 10.hours.ago)

      expect {
        delete "/pipeline_runs/orphans"
      }.to change(LegislationPipelineRun, :count).by(-2)

      expect(LegislationPipelineRun.exists?(orphan_a.id)).to be false
      expect(LegislationPipelineRun.exists?(orphan_b.id)).to be false
    end

    it "emits an orphan_run_deleted activity log entry per deleted row" do
      create(:legislation_pipeline_run, status: "running", created_at: 5.hours.ago)
      create(:legislation_pipeline_run, status: "queued", created_at: 10.hours.ago)

      expect {
        delete "/pipeline_runs/orphans"
      }.to change(PipelineActivityLogEntry.where(event_type: "orphan_run_deleted"), :count).by(2)
    end

    it "does NOT delete rows younger than 4 hours (age gate)" do
      young = create(:legislation_pipeline_run, status: "running", created_at: 1.hour.ago)

      expect {
        delete "/pipeline_runs/orphans"
      }.not_to change(LegislationPipelineRun, :count)
      expect(LegislationPipelineRun.exists?(young.id)).to be true
    end

    it "does NOT delete rows in terminal status (status gate)" do
      done = create(:legislation_pipeline_run, status: "succeeded", created_at: 5.hours.ago)
      failed = create(:legislation_pipeline_run, status: "failed", created_at: 5.hours.ago)

      expect {
        delete "/pipeline_runs/orphans"
      }.not_to change(LegislationPipelineRun, :count)
      expect(LegislationPipelineRun.exists?(done.id)).to be true
      expect(LegislationPipelineRun.exists?(failed.id)).to be true
    end

    it "does NOT delete rows with a live SolidQueue job (SQ gate)" do
      protected = create(:legislation_pipeline_run, status: "running", created_at: 5.hours.ago)
      allow(LegislationPipelineRun).to receive(:solid_queue_job_exists_for?)
        .with(an_instance_of(LegislationPipelineRun))
        .and_return(true)

      expect {
        delete "/pipeline_runs/orphans"
      }.not_to change(LegislationPipelineRun, :count)
      expect(LegislationPipelineRun.exists?(protected.id)).to be true
    end

    it "is a no-op when no orphans exist (no count change, no log entries, friendly flash)" do
      expect {
        delete "/pipeline_runs/orphans"
      }.not_to change(LegislationPipelineRun, :count)
      expect(PipelineActivityLogEntry.where(event_type: "orphan_run_deleted").count).to eq(0)
      expect(flash[:notice]).to eq("No orphan runs to remove.")
    end

    it "writes a flash[:notice] summarizing the actual delete count + ids" do
      orphan = create(:legislation_pipeline_run, status: "running", created_at: 5.hours.ago)
      delete "/pipeline_runs/orphans"
      expect(flash[:notice]).to eq("Removed 1 orphan run (#{orphan.id}).")
    end

    it "pluralizes the flash notice for 2+ deletes" do
      o1 = create(:legislation_pipeline_run, status: "running", created_at: 5.hours.ago)
      o2 = create(:legislation_pipeline_run, status: "queued", created_at: 5.hours.ago)
      delete "/pipeline_runs/orphans"
      expect(flash[:notice]).to eq("Removed 2 orphan runs (#{o1.id}, #{o2.id}).")
    end

    it "skips guarded rows but still deletes eligible siblings in the same call" do
      deletable = create(:legislation_pipeline_run, status: "running", created_at: 5.hours.ago)
      protected_run = create(:legislation_pipeline_run, status: "running", created_at: 5.hours.ago)
      allow(LegislationPipelineRun).to receive(:solid_queue_job_exists_for?) do |run|
        run.id == protected_run.id
      end

      expect {
        delete "/pipeline_runs/orphans"
      }.to change(LegislationPipelineRun, :count).by(-1)

      expect(LegislationPipelineRun.exists?(deletable.id)).to be false
      expect(LegislationPipelineRun.exists?(protected_run.id)).to be true
    end

    it "redirects to /bills/new pipeline tab when back_to=bill_creator is set" do
      delete "/pipeline_runs/orphans?back_to=bill_creator"
      expect(response).to redirect_to(new_bill_creator_path(bill_creator_tab: :pipeline))
    end

    it "redirects to /pipeline_runs by default" do
      delete "/pipeline_runs/orphans"
      expect(response).to redirect_to(pipeline_runs_path)
    end

    # The difference from sweep_stale_pipeline_runs: the sweep marks queued and
    # running rows failed and keeps them, while this endpoint really deletes
    # them. Asserted here so that anyone merging the two operations later
    # cannot break it quietly.
    it "hard-deletes (not marks failed) — distinguishes from sweep_stale_pipeline_runs" do
      orphan = create(:legislation_pipeline_run, status: "running", created_at: 5.hours.ago)
      orphan_id = orphan.id
      delete "/pipeline_runs/orphans"
      expect(LegislationPipelineRun.exists?(orphan_id)).to be false
      expect(LegislationPipelineRun.unscoped.exists?(orphan_id)).to be false
    end
  end
end
