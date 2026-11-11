# frozen_string_literal: true

require "rails_helper"

# @lat: [[pipeline-controls-state-url-contract#Query params this hook owns#usePipelineControlsState.test.ts notes on keeping the rest of the query string]]
# Seven canonical stage keys now (fetch-law and summarize-bill joined the original five); download_missing_assets defaults to true.
RSpec.describe BillsController, type: :request do
  include_context "SessionDouble"

  let(:admin) { create(:user, :sway_admin) }
  let(:bill) { create(:bill) }

  before do
    sign_in admin
    # As soon as one stage is selected, bill_creator_props asks
    # PipelinePreviewService.fetch for a preview by way of pipeline_preview_for. Hand
    # back nil instead, so these tests stay on the control props and do not depend on
    # what a preview looks like.
    allow(PipelinePreviewService).to receive(:fetch).and_return(nil)
  end

  describe "pipeline_controls_state Inertia props" do
    it "defaults selected_stages to the 7 non-summary stages (summarize-bill off) when no param is given" do
      get "/admin/bill_creator/#{bill.id}/pipeline"
      expect(response).to have_http_status(:ok)
      expect(inertia).to render_component(Pages::BILL_CREATOR)
      expect(inertia.props[:selected_stages]).to eq(%w[fetch-bills fetch-law extract-text parse-sections generate-diffs fetch-hearings clean-testimony])
      expect(inertia.props[:selected_stages]).not_to include("summarize-bill")
    end

    # @lat: [[admin-hub-and-tabs#Each Bill Creator tab has its own path]]
    it "reflects the path bill id in the picker and defaults download_missing_assets to true" do
      get "/admin/bill_creator/#{bill.id}/pipeline"
      expect(inertia.props[:bill_id]).to eq(bill.id.to_s)
      expect(inertia.props[:download_missing_assets]).to be(true)
    end

    it "defaults bill_id to empty string on the id-less all-bills (#new) flow" do
      get "/admin/bill_creator/new"
      expect(inertia.props[:bill_id]).to eq("")
      expect(inertia.props[:download_missing_assets]).to be(true)
    end

    it "echoes selected_stages from query param when provided as array" do
      get "/admin/bill_creator/#{bill.id}/pipeline", params: {selected_stages: ["fetch-bills", "extract-text"]}
      expect(inertia.props[:selected_stages]).to eq(%w[fetch-bills extract-text])
    end

    it "parses selected_stages comma-separated string form" do
      get "/admin/bill_creator/#{bill.id}/pipeline", params: {selected_stages: "fetch-bills,parse-sections"}
      expect(inertia.props[:selected_stages]).to eq(%w[fetch-bills parse-sections])
    end

    it "accepts fetch-law and summarize-bill in selected_stages (allowlist expansion)" do
      get "/admin/bill_creator/#{bill.id}/pipeline", params: {selected_stages: ["fetch-law", "summarize-bill"]}
      expect(inertia.props[:selected_stages]).to eq(%w[fetch-law summarize-bill])
    end

    it "drops unknown stage keys silently (allow-list defense)" do
      get "/admin/bill_creator/#{bill.id}/pipeline", params: {selected_stages: ["fetch-bills", "garbage"]}
      expect(inertia.props[:selected_stages]).to eq(%w[fetch-bills])
    end

    it "echoes bill_id from query param on the id-less all-bills (#new) flow (wire field)" do
      # #new has no id in its path, so `?bill_id=` is the only thing that can tell the
      # picker which bill is selected.
      get "/admin/bill_creator/new", params: {bill_id: "42"}
      expect(inertia.props[:bill_id]).to eq("42")
    end

    it "casts download_missing_assets '0' to false" do
      get "/admin/bill_creator/#{bill.id}/pipeline", params: {download_missing_assets: "0"}
      expect(inertia.props[:download_missing_assets]).to be(false)
    end

    it "casts download_missing_assets 'true' to true" do
      get "/admin/bill_creator/#{bill.id}/pipeline", params: {download_missing_assets: "true"}
      expect(inertia.props[:download_missing_assets]).to be(true)
    end

    it "treats explicit empty selected_stages as 'none selected' (does not refill defaults)" do
      get "/admin/bill_creator/#{bill.id}/pipeline", params: {
        selected_stages: [] #: Array[untyped]
      }
      expect(inertia.props[:selected_stages]).to eq([])
    end

    # @lat: [[pipeline-controls-empty-stage-selection-wire-format#Why an empty stage selection has to be spelled out on the wire]]
    it "reads ?selected_stages= as 'none selected'" do
      get "/admin/bill_creator/#{bill.id}/pipeline?selected_stages="
      expect(inertia.props[:selected_stages]).to eq([])
    end

    it "reads an absent selected_stages as DEFAULT_PIPELINE_STAGE_KEYS (summarize-bill off)" do
      get "/admin/bill_creator/#{bill.id}/pipeline"
      expect(inertia.props[:selected_stages]).to eq(BillsController::DEFAULT_PIPELINE_STAGE_KEYS)
    end

    # @lat: [[pipeline-controls-state-url-contract#Query params this hook owns#usePipelineControlsState.test.ts notes on the legacy ?stages= name]]
    it "falls back to legacy ?stages= for fetch-law and fetch-bills (allowlist expansion)" do
      get "/admin/bill_creator/#{bill.id}/pipeline", params: {stages: "fetch-bills,fetch-law"}
      expect(inertia.props[:selected_stages]).to eq(%w[fetch-bills fetch-law])
    end

    it "falls back to legacy ?stages= for ALL allow-listed stages (LOW-16-2)" do
      get "/admin/bill_creator/#{bill.id}/pipeline", params: {stages: "fetch-bills,extract-text"}
      expect(inertia.props[:selected_stages]).to eq(%w[fetch-bills extract-text])
    end

    it "prefers ?selected_stages= over ?stages= when both are present (LOW-16-2)" do
      get "/admin/bill_creator/#{bill.id}/pipeline",
        params: {selected_stages: ["parse-sections"], stages: "fetch-bills"}
      expect(inertia.props[:selected_stages]).to eq(%w[parse-sections])
    end

    it "does not expose show_restart_menu (Plan 55-06 RM-03)" do
      get "/admin/bill_creator/#{bill.id}/pipeline"
      expect(inertia.props.keys).not_to include(:show_restart_menu)
    end

    it "does not expose show_restart_refresh_dialog (Plan 55-06 RM-05)" do
      get "/admin/bill_creator/#{bill.id}/pipeline"
      expect(inertia.props.keys).not_to include(:show_restart_refresh_dialog)
    end
  end

  # The controller has to pass both `bills:` and `download_missing_assets:` down to
  # PipelinePreviewService. Without them, the preview cannot tell which stages are
  # missing something they need (`prereq_violations`, which feeds the warning banner),
  # nor trim the stage list by which artifacts already exist.
  describe "pipeline_preview plumbing — CR-01" do
    before do
      # Let the real service run, so the test sees the actual arguments the controller
      # passes along.
      allow(PipelinePreviewService).to receive(:fetch).and_call_original
    end

    it "forwards a bill-scoped relation and download_missing_assets to PipelinePreviewService.fetch on #edit" do
      get "/admin/bill_creator/#{bill.id}/pipeline",
        params: {selected_stages: ["parse-sections"], download_missing_assets: "0"}

      expect(PipelinePreviewService).to have_received(:fetch).at_least(:once) do |stages:, download_missing_assets:, bills:|
        expect(stages).to eq(%w[parse-sections])
        expect(download_missing_assets).to eq(false)
        expect(bills).to respond_to(:where)
        ids = bills.respond_to?(:ids) ? bills.ids : bills.map(&:id)
        expect(ids).to include(bill.id)
      end
    end

    it "surfaces prereq_violations in pipeline_preview when the bill is missing the prerequisite artifact and download_missing_assets is off" do
      # This bill has no extracted text and no section refs, and parse-sections needs
      # extract-text to have run first. With downloading of missing assets switched
      # off, the preview has to report at least one prerequisite violation.
      get "/admin/bill_creator/#{bill.id}/pipeline",
        params: {selected_stages: ["parse-sections"], download_missing_assets: "0"}

      preview = inertia.props[:pipeline_preview]
      expect(preview).to be_a(Hash)
      expect(preview["prereq_violations"]).to be_a(Array)
      expect(preview["prereq_violations"]).not_to be_empty
      first = preview["prereq_violations"].first
      expect(first["stage"]).to eq("parse-sections")
      expect(first["bill_count"]).to be >= 1
    end
  end

  # @lat: [[legislation-pipeline-run-sourcing-concern#Why legislation_pipeline_run_props reads active_any, not active_global]]
  describe "legislation_pipeline_run sourcing — CR-03 (concern uses active_any)" do
    it "exposes a running SINGLE-BILL run via the legislation_pipeline_run Inertia prop" do
      single_bill_run = LegislationPipelineRun.create!(
        stages: ["fetch-bills"], status: "running", bill_id: bill.id
      )

      get "/admin/bill_creator/#{bill.id}/pipeline"

      prop = inertia.props[:legislation_pipeline_run]
      expect(prop).not_to be_nil, "expected concern to surface single-bill run via active_any"
      expect(prop[:id]).to eq(single_bill_run.id)
      expect(prop[:status]).to eq("running")
    end

    # @lat: [[legislation-pipeline#The legislation pipeline#Runs, resume and restart#Stuck runs require evidence of abandonment]]
    it "shows a newly started run as active without labeling it stuck" do
      run = LegislationPipelineRun.create!(stages: ["fetch-bills"], status: "running", bill_id: bill.id)

      get "/admin/bill_creator/#{bill.id}/pipeline"

      expect(inertia).to have_props(stale_pipeline_run_count: 0)
      expect(inertia.props[:active_legislation_pipeline_run][:id]).to eq(run.id)
    end

    it "counts only abandoned runs across single-bill, all-bills and summary-batch states" do
      allow(LegislationPipelineRun).to receive(:solid_queue_job_exists_for?).and_return(false)
      owned = create(:legislation_pipeline_run, status: "running", updated_at: 5.hours.ago)
      allow(LegislationPipelineRun).to receive(:solid_queue_job_exists_for?).with(owned).and_return(true)
      create(:legislation_pipeline_run, bill: bill, status: "fetching_law", updated_at: 5.hours.ago)
      create(:legislation_pipeline_run, status: "queued", updated_at: 5.hours.ago)
      create(:legislation_pipeline_run, status: "running", created_at: 1.day.ago)
      awaiting = create(:legislation_pipeline_run, status: "awaiting_summary_batch", updated_at: 5.hours.ago)
      create(:pipeline_run_summary_batch, legislation_pipeline_run: awaiting)
      expired = create(:legislation_pipeline_run, status: "awaiting_summary_batch", updated_at: 5.hours.ago)
      create(:pipeline_run_summary_batch, :expired, legislation_pipeline_run: expired)

      get "/admin/bill_creator/new", params: {tab_key: "pipeline"}

      expect(inertia).to have_props(stale_pipeline_run_count: 3)
    end
  end

  # @lat: [[legislation-pipeline-run-sourcing-concern#Why surfaced_pipeline_run falls back to successful runs]]
  describe "legislation_pipeline_run sourcing — UAT-4 (failed-run recovery affordance)" do
    it "surfaces a force-failed SINGLE-BILL run via the legislation_pipeline_run prop" do
      failed_run = LegislationPipelineRun.create!(
        stages: ["summarize-bill"], status: "failed", bill_id: bill.id
      )

      get "/admin/bill_creator/#{bill.id}/pipeline"

      prop = inertia.props[:legislation_pipeline_run]
      expect(prop).not_to be_nil, "expected concern to surface failed single-bill run for Restart affordance"
      expect(prop[:id]).to eq(failed_run.id)
      expect(prop[:status]).to eq("failed")
      expect(prop[:kind]).to eq("single")
    end

    it "surfaces a force-failed ALL-BILLS run via the legislation_pipeline_run prop" do
      failed_run = LegislationPipelineRun.create!(
        stages: ["fetch-bills"], status: "failed", bill_id: nil
      )

      get "/admin/bill_creator/#{bill.id}/pipeline"

      prop = inertia.props[:legislation_pipeline_run]
      expect(prop).not_to be_nil
      expect(prop[:id]).to eq(failed_run.id)
      expect(prop[:status]).to eq("failed")
      expect(prop[:kind]).to eq("all_bills")
    end

    it "surfaces a SUCCEEDED run but drives no recovery affordance (Resume/Restart gate on status)" do
      succeeded_run = LegislationPipelineRun.create!(
        stages: ["fetch-bills"], status: "succeeded", bill_id: bill.id
      )

      get "/admin/bill_creator/#{bill.id}/pipeline"

      # LegislationPipelineRunSourcing#surfaced_pipeline_run deliberately returns the
      # newest run whatever its status, succeeded included — see the step-3 comment in
      # that code. The React side draws no Resume or Restart button unless the status is
      # failed, so handing over a succeeded run changes nothing on screen.
      prop = inertia.props[:legislation_pipeline_run]
      expect(prop).not_to be_nil
      expect(prop[:id]).to eq(succeeded_run.id)
      expect(prop[:status]).to eq("succeeded")
    end

    it "prefers an active run over a failed run when both exist" do
      LegislationPipelineRun.create!(
        stages: ["fetch-bills"], status: "failed", bill_id: bill.id
      )
      active_run = LegislationPipelineRun.create!(
        stages: ["fetch-bills"], status: "running", bill_id: bill.id
      )

      get "/admin/bill_creator/#{bill.id}/pipeline"

      prop = inertia.props[:legislation_pipeline_run]
      expect(prop[:id]).to eq(active_run.id)
      expect(prop[:status]).to eq("running")
    end

    it "does NOT count a failed run in stale_pipeline_run_count" do
      LegislationPipelineRun.create!(
        stages: ["fetch-bills"], status: "failed", bill_id: bill.id
      )

      get "/admin/bill_creator/#{bill.id}/pipeline"

      expect(inertia.props[:stale_pipeline_run_count]).to eq(0)
    end
  end
end
