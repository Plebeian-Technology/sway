# frozen_string_literal: true

# == Schema Information
#
# Table name: legislation_pipeline_run_bills
# Database name: primary
#
#  id                          :integer          not null, primary key
#  error_message               :text
#  finished_at                 :datetime
#  sort_order                  :integer          default(0), not null
#  stage_results               :json             not null
#  started_at                  :datetime
#  status                      :string           default("pending"), not null
#  created_at                  :datetime         not null
#  updated_at                  :datetime         not null
#  bill_external_id            :string           not null
#  legislation_pipeline_run_id :integer          not null
#
# Indexes
#
#  idx_on_legislation_pipeline_run_id_1cc054cf9b             (legislation_pipeline_run_id)
#  index_legislation_pipeline_run_bills_on_bill_external_id  (bill_external_id)
#  index_prb_on_run_and_bill_external_id                     (legislation_pipeline_run_id,bill_external_id) UNIQUE
#
# Foreign Keys
#
#  legislation_pipeline_run_id  (legislation_pipeline_run_id => legislation_pipeline_runs.id) ON DELETE => cascade
#
require "rails_helper"

RSpec.describe PipelineRunBill, type: :model do
  describe "factory" do
    it "produces a valid record" do
      expect(build(:pipeline_run_bill)).to be_valid
    end

    [:running, :succeeded, :failed, :skipped].each do |trait|
      it "produces a valid record with trait :#{trait}" do
        expect(build(:pipeline_run_bill, trait)).to be_valid
      end
    end
  end

  describe "associations" do
    it "belongs_to :legislation_pipeline_run" do
      bill = create(:pipeline_run_bill)
      expect(bill.legislation_pipeline_run).to be_a(LegislationPipelineRun)
    end
  end

  describe "state machine" do
    it "starts in pending status" do
      bill = build(:pipeline_run_bill)
      expect(bill.status).to eq("pending")
    end

    describe "#start_running!" do
      it "transitions pending → running" do
        bill = create(:pipeline_run_bill)
        expect { bill.start_running! }.to change(bill, :status).from("pending").to("running")
      end

      it "raises StateMachines::InvalidTransition when called from running" do
        bill = create(:pipeline_run_bill, :running)
        expect { bill.start_running! }.to raise_error(StateMachines::InvalidTransition)
      end

      # Record started_at as the bill starts running, so the per-bill grid's "Started"
      # column can show "3 minutes ago" instead of a dash.
      it "stamps started_at on pending → running" do
        bill = create(:pipeline_run_bill, started_at: nil)
        expect { bill.start_running! }.to change { bill.reload.started_at }.from(nil)
        expect(bill.started_at).to be_within(5.seconds).of(Time.current)
      end

      it "preserves an externally-set started_at" do
        prior = 3.hours.ago
        bill = create(:pipeline_run_bill, started_at: prior)
        bill.start_running!
        expect(bill.reload.started_at).to be_within(1.second).of(prior)
      end
    end

    describe "#mark_succeeded!" do
      it "transitions running → succeeded" do
        bill = create(:pipeline_run_bill, :running)
        expect { bill.mark_succeeded! }.to change(bill, :status).from("running").to("succeeded")
      end

      it "raises StateMachines::InvalidTransition when called from pending" do
        bill = create(:pipeline_run_bill)
        expect { bill.mark_succeeded! }.to raise_error(StateMachines::InvalidTransition)
      end

      # Record finished_at when the bill reaches a final state, so the per-bill grid can
      # show how long each one took instead of rows that all look alike.
      it "stamps finished_at on running → succeeded" do
        bill = create(:pipeline_run_bill, :running, finished_at: nil)
        expect { bill.mark_succeeded! }.to change { bill.reload.finished_at }.from(nil)
        expect(bill.finished_at).to be_within(5.seconds).of(Time.current)
      end
    end

    describe "#mark_failed!" do
      it "transitions running → failed" do
        bill = create(:pipeline_run_bill, :running)
        expect { bill.mark_failed! }.to change(bill, :status).from("running").to("failed")
      end

      it "transitions pending → failed" do
        bill = create(:pipeline_run_bill)
        expect { bill.mark_failed! }.to change(bill, :status).from("pending").to("failed")
      end
    end

    describe "#mark_skipped!" do
      it "transitions pending → skipped" do
        bill = create(:pipeline_run_bill)
        expect { bill.mark_skipped! }.to change(bill, :status).from("pending").to("skipped")
      end

      it "raises StateMachines::InvalidTransition when called from running" do
        bill = create(:pipeline_run_bill, :running)
        expect { bill.mark_skipped! }.to raise_error(StateMachines::InvalidTransition)
      end
    end

    it "raises StateMachines::InvalidTransition for succeeded → running" do
      bill = create(:pipeline_run_bill, :succeeded)
      expect { bill.start_running! }.to raise_error(StateMachines::InvalidTransition)
    end

    it "raises StateMachines::InvalidTransition for skipped → running" do
      bill = create(:pipeline_run_bill, :skipped)
      expect { bill.start_running! }.to raise_error(StateMachines::InvalidTransition)
    end
  end

  # @lat: [[pipeline-run-bill-lifecycle#Why LegislationPipelineRun's pipeline_run_bills association orders by sort_order]]
  describe "sort_order monotonic invariant" do
    it "rejects updates to sort_order on a persisted record" do
      bill_run = create(:pipeline_run_bill, sort_order: 5)
      bill_run.sort_order = 6
      # ActiveRecord spells the column name out in its error message: "Sort order ..."
      expect { bill_run.save! }.to raise_error(ActiveRecord::RecordInvalid, /sort order/i)
    end

    it "allows other column updates without raising" do
      bill_run = create(:pipeline_run_bill, sort_order: 5)
      expect { bill_run.update!(error_message: "anything") }.not_to raise_error
    end

    it "permits the initial assignment on create" do
      run = create(:legislation_pipeline_run)
      expect {
        described_class.create!(
          legislation_pipeline_run: run,
          bill_external_id: "WR-08-CREATE-OK",
          sort_order: 42
        )
      }.not_to raise_error
    end

    # @lat: [[pipeline-run-bill-lifecycle#Why LegislationPipelineRun's pipeline_run_bills association orders by sort_order]]
    it "permits update_columns(sort_order: ...) as the documented escape hatch (WR-NEW-04)" do
      bill_run = create(:pipeline_run_bill, sort_order: 5)
      expect { bill_run.update_columns(sort_order: 7) }.not_to raise_error
      expect(bill_run.reload.sort_order).to eq(7)
    end
  end

  # @lat: [[pipeline-run-bill-lifecycle#Why LegislationPipelineRun's pipeline_run_bills association orders by sort_order]]
  describe "audit-log (in-transition) + broadcast (after-commit) split" do
    before do
      allow(PipelineActivityLogger).to receive(:emit_bill_transition!)
      allow(PipelineRunChannel).to receive(:broadcast_to)
    end

    it "emits exactly one emit_bill_transition! call per transition" do
      bill_run = create(:pipeline_run_bill)
      bill_run.start_running!
      expect(PipelineActivityLogger).to have_received(:emit_bill_transition!).with(
        bill_run: bill_run, from: "pending", to: "running", event: :start_running
      ).once
    end

    it "emits exactly one broadcast per transition with scope: \"bill\" and run_id matching legislation_pipeline_run_id" do
      bill_run = create(:pipeline_run_bill)
      bill_run.start_running!
      expect(PipelineRunChannel).to have_received(:broadcast_to).with(
        anything,
        hash_including(
          scope: "bill",
          run_id: bill_run.legislation_pipeline_run_id,
          bill_run_id: bill_run.id,
          status: "running"
        )
      ).once
    end

    it "does NOT broadcast and does NOT emit_bill_transition! when update_columns writes only stage_results (Plan 07 path)" do
      bill_run = create(:pipeline_run_bill, :running)
      bill_run.update_columns(stage_results: {"fetch_bills" => {"status" => "succeeded"}})
      expect(PipelineRunChannel).not_to have_received(:broadcast_to)
      expect(PipelineActivityLogger).not_to have_received(:emit_bill_transition!)
    end

    it "rolls back the transition AND does NOT broadcast when emit_bill_transition! raises" do
      bill_run = create(:pipeline_run_bill)
      allow(PipelineActivityLogger).to receive(:emit_bill_transition!).and_raise(StandardError, "boom")

      expect { bill_run.start_running! }.to raise_error(StandardError, "boom")
      expect(bill_run.reload.status).to eq("pending")
      expect(PipelineRunChannel).not_to have_received(:broadcast_to)
    end
  end
end
