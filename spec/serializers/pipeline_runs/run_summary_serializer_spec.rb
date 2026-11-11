# frozen_string_literal: true

require "rails_helper"

# The shape of the props the /pipeline_runs index page receives. This replaces
# a raw `.map(&:attributes)` dump, which lost information, with one worked-out
# summary row per run: id, status, kind, started_at and completed_at, bill
# counts, and the failing stage.
RSpec.describe PipelineRuns::RunSummarySerializer do
  describe ".call" do
    context "when no runs exist" do
      it "returns an empty array" do
        expect(described_class.call(LegislationPipelineRun.none)).to eq([])
      end
    end

    context "with a global all-bills run" do
      let!(:run) do
        create(:legislation_pipeline_run, :running,
          started_at: Time.utc(2026, 5, 13, 10, 0, 0),
          completed_at: nil,
          current_stage: "extract_text")
      end
      let!(:succeeded_bill) do
        create(:pipeline_run_bill,
          legislation_pipeline_run: run,
          bill_external_id: "25-0001",
          status: "succeeded")
      end
      let!(:failed_bill) do
        create(:pipeline_run_bill,
          legislation_pipeline_run: run,
          bill_external_id: "25-0002",
          status: "failed")
      end
      let!(:running_bill) do
        create(:pipeline_run_bill,
          legislation_pipeline_run: run,
          bill_external_id: "25-0003",
          status: "running")
      end

      it "emits one row per run with the locked summary shape" do
        rows = described_class.call(LegislationPipelineRun.where(id: run.id))
        expect(rows.length).to eq(1)
        row = rows.first
        expect(row.keys).to match_array(
          # remote_run_id is the PipelineRunChannel stream name the front-end
          # Index page subscribes to so it updates itself.
          %i[id status kind bill_id bill_external_id remote_run_id started_at completed_at current_stage bills_total bills_succeeded bills_failed failing_stage]
        )
      end

      it "reports derived counts from pipeline_run_bills" do
        rows = described_class.call(LegislationPipelineRun.where(id: run.id))
        row = rows.first
        expect(row[:bills_total]).to eq(3)
        expect(row[:bills_succeeded]).to eq(1)
        expect(row[:bills_failed]).to eq(1)
      end

      it "infers kind = 'all_bills' when bill_id is blank" do
        rows = described_class.call(LegislationPipelineRun.where(id: run.id))
        expect(rows.first[:kind]).to eq("all_bills")
        expect(rows.first[:bill_id]).to be_nil
        expect(rows.first[:bill_external_id]).to be_nil
      end

      it "echoes started_at/completed_at as ISO8601 strings" do
        rows = described_class.call(LegislationPipelineRun.where(id: run.id))
        row = rows.first
        expect(row[:started_at]).to eq("2026-05-13T10:00:00Z")
        expect(row[:completed_at]).to be_nil
      end
    end

    context "with a single-bill run (bill_id present)" do
      let!(:scoped_bill) { create(:bill, external_id: "25-0007") }
      let!(:run) { create(:legislation_pipeline_run, :running, bill: scoped_bill) }

      it "infers kind = 'single' and echoes bill_id + bill_external_id" do
        rows = described_class.call(LegislationPipelineRun.where(id: run.id))
        expect(rows.first[:kind]).to eq("single")
        expect(rows.first[:bill_id]).to eq(scoped_bill.id)
        expect(rows.first[:bill_external_id]).to eq("25-0007")
      end
    end

    context "with a failed run that has a failed pipeline_run_stage" do
      let!(:run) { create(:legislation_pipeline_run, :failed) }
      let!(:failed_stage) do
        run.pipeline_run_stages.create!(
          stage_name: "extract_text",
          status: "failed"
        )
      end
      let!(:succeeded_stage) do
        run.pipeline_run_stages.create!(
          stage_name: "fetch_bills",
          status: "succeeded"
        )
      end

      it "reports failing_stage = the first failed pipeline_run_stage" do
        rows = described_class.call(LegislationPipelineRun.where(id: run.id))
        expect(rows.first[:failing_stage]).to eq("extract_text")
      end
    end

    context "with a clean run that has no failed stages" do
      let!(:run) { create(:legislation_pipeline_run, :completed) }

      it "reports failing_stage = nil" do
        rows = described_class.call(LegislationPipelineRun.where(id: run.id))
        expect(rows.first[:failing_stage]).to be_nil
      end
    end

    context "ordering" do
      let!(:older) { create(:legislation_pipeline_run, :completed, created_at: 2.days.ago) }
      let!(:newer) { create(:legislation_pipeline_run, :running, created_at: 1.hour.ago) }

      it "preserves the relation's ORDER BY clause (caller-supplied)" do
        scope = LegislationPipelineRun.order(created_at: :desc)
        rows = described_class.call(scope)
        expect(rows.pluck(:id)).to eq([newer.id, older.id])
      end
    end
  end
end
