# frozen_string_literal: true

# == Schema Information
#
# Table name: legislation_pipeline_run_stages
# Database name: primary
#
#  id                          :integer          not null, primary key
#  completed_bill_external_ids :text             default([]), not null
#  error_message               :text
#  finished_at                 :datetime
#  output_summary              :text
#  remaining_bill_external_ids :text             default([]), not null
#  stage_name                  :string           not null
#  started_at                  :datetime
#  status                      :string           default("pending"), not null
#  created_at                  :datetime         not null
#  updated_at                  :datetime         not null
#  legislation_pipeline_run_id :integer          not null
#
# Indexes
#
#  idx_on_legislation_pipeline_run_id_c51e3ef6b9  (legislation_pipeline_run_id)
#  index_prs_on_run_and_stage_name                (legislation_pipeline_run_id,stage_name) UNIQUE
#
# Foreign Keys
#
#  legislation_pipeline_run_id  (legislation_pipeline_run_id => legislation_pipeline_runs.id) ON DELETE => cascade
#
require "rails_helper"

RSpec.describe PipelineRunStage, type: :model do
  describe "factory" do
    it "produces a valid record" do
      expect(build(:pipeline_run_stage)).to be_valid
    end

    [:running, :succeeded, :failed, :skipped, :cancelled, :with_extract_text_summary].each do |trait|
      it "produces a valid record with trait :#{trait}" do
        expect(build(:pipeline_run_stage, trait)).to be_valid
      end
    end
  end

  describe "associations" do
    it "belongs_to :legislation_pipeline_run" do
      stage = create(:pipeline_run_stage)
      expect(stage.legislation_pipeline_run).to be_a(LegislationPipelineRun)
    end
  end

  describe "state machine" do
    it "starts in pending status" do
      stage = build(:pipeline_run_stage)
      expect(stage.status).to eq("pending")
    end

    describe "#start_running!" do
      it "transitions pending → running" do
        stage = create(:pipeline_run_stage)
        expect { stage.start_running! }.to change(stage, :status).from("pending").to("running")
      end

      it "raises StateMachines::InvalidTransition when called from running" do
        stage = create(:pipeline_run_stage, :running)
        expect { stage.start_running! }.to raise_error(StateMachines::InvalidTransition)
      end
    end

    describe "#mark_succeeded!" do
      it "transitions running → succeeded" do
        stage = create(:pipeline_run_stage, :running)
        expect { stage.mark_succeeded! }.to change(stage, :status).from("running").to("succeeded")
      end

      it "raises StateMachines::InvalidTransition when called from pending" do
        stage = create(:pipeline_run_stage)
        expect { stage.mark_succeeded! }.to raise_error(StateMachines::InvalidTransition)
      end
    end

    describe "#mark_failed!" do
      it "transitions running → failed" do
        stage = create(:pipeline_run_stage, :running)
        expect { stage.mark_failed! }.to change(stage, :status).from("running").to("failed")
      end

      it "transitions pending → failed" do
        stage = create(:pipeline_run_stage)
        expect { stage.mark_failed! }.to change(stage, :status).from("pending").to("failed")
      end
    end

    describe "#mark_skipped!" do
      it "transitions pending → skipped" do
        stage = create(:pipeline_run_stage)
        expect { stage.mark_skipped! }.to change(stage, :status).from("pending").to("skipped")
      end

      it "raises StateMachines::InvalidTransition when called from running" do
        stage = create(:pipeline_run_stage, :running)
        expect { stage.mark_skipped! }.to raise_error(StateMachines::InvalidTransition)
      end
    end

    describe "#mark_cancelled!" do
      it "transitions running → cancelled" do
        stage = create(:pipeline_run_stage, :running)
        expect { stage.mark_cancelled! }.to change(stage, :status).from("running").to("cancelled")
      end

      it "transitions pending → cancelled" do
        stage = create(:pipeline_run_stage)
        expect { stage.mark_cancelled! }.to change(stage, :status).from("pending").to("cancelled")
      end
    end

    it "raises StateMachines::InvalidTransition for succeeded → running" do
      stage = create(:pipeline_run_stage, :succeeded)
      expect { stage.start_running! }.to raise_error(StateMachines::InvalidTransition)
    end

    it "raises StateMachines::InvalidTransition for skipped → running" do
      stage = create(:pipeline_run_stage, :skipped)
      expect { stage.start_running! }.to raise_error(StateMachines::InvalidTransition)
    end
  end

  describe "JSON column round-trips (Pitfall #4)" do
    it "round-trips JSON arrays for completed_bill_external_ids and remaining_bill_external_ids" do
      stage = create(:pipeline_run_stage,
        completed_bill_external_ids: ["bill_1", "bill_2"],
        remaining_bill_external_ids: ["bill_3"])
      stage.reload
      expect(stage.completed_bill_external_ids).to eq(["bill_1", "bill_2"])
      expect(stage.remaining_bill_external_ids).to eq(["bill_3"])
    end

    it "round-trips output_summary as a hash via coder: JSON" do
      stage = create(:pipeline_run_stage, :with_extract_text_summary)
      stage.reload
      expect(stage.output_summary).to eq(
        "pages" => 12,
        "ocr_used" => false,
        "tesseract_invocations" => 0,
        "output_path" => "/tmp/extract_text/test.txt"
      )
    end
  end

  describe "#mark_bill_completed!" do
    it "moves bill from remaining to completed" do
      stage = create(:pipeline_run_stage, :running)
      stage.mark_bill_completed!("bill_2")
      stage.reload
      expect(stage.remaining_bill_external_ids).to eq(["bill_1", "bill_3"])
      expect(stage.completed_bill_external_ids).to eq(["bill_2"])
    end

    it "is idempotent — second call does not duplicate" do
      stage = create(:pipeline_run_stage, :running)
      stage.mark_bill_completed!("bill_2")
      stage.mark_bill_completed!("bill_2")
      stage.reload
      expect(stage.completed_bill_external_ids).to eq(["bill_2"])
    end

    it "is a no-op when bill_external_id is not in remaining (monotonic invariant)" do
      stage = create(:pipeline_run_stage, :running)
      expect {
        stage.mark_bill_completed!("bill_not_there")
      }.not_to(change { stage.reload.completed_bill_external_ids })
    end

    it "uses with_lock to serialize concurrent writers" do
      # Read the model's own source and confirm mark_bill_completed! uses with_lock.
      model_path = Rails.root.join("app", "models", "pipeline_run_stage.rb").to_s
      model_source = File.read(model_path)
      expect(model_source).to include("with_lock")
    end
  end
end
