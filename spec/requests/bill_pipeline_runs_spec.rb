require "rails_helper"

RSpec.describe "Bill pipeline runs run_pipeline admin gate", type: :request do
  include_examples "requires sway admin",
    verb: :post,
    path: "/bills/run_pipeline",
    params: {stages: ["fetch-bills"]}
end

RSpec.describe "Bill pipeline runs sweep_stale_pipeline_runs admin gate", type: :request do
  include_examples "requires sway admin",
    verb: :post,
    path: "/bills/sweep_stale_pipeline_runs"
end

RSpec.describe "Bill pipeline runs", type: :request do
  let(:admin) { create(:user, :sway_admin) }
  let(:sway_locale) { create(:sway_locale, :baltimore) }

  before { sign_in admin }

  describe "POST /bills/run_pipeline" do
    it "creates a LegislationPipelineRun and redirects to edit_bill_creator_path" do
      expect {
        post "/bills/run_pipeline", params: {stages: ["fetch-bills", "extract-text"], sway_locale_id: sway_locale.id}
      }.to change(LegislationPipelineRun, :count).by(1)
      expect(response).to have_http_status(:redirect)
      expect(LegislationPipelineRun.last&.sway_locale_id).to eq(sway_locale.id)
    end

    it "refuses all-bills runs when sway_locale_id is missing" do
      expect {
        post "/bills/run_pipeline", params: {stages: ["fetch-bills"]}
      }.not_to change(LegislationPipelineRun, :count)
      expect(response).to have_http_status(:redirect)
      follow_redirect!
      expect(response.body).to include("A SwayLocale is required for all-bills pipeline runs.")
    end

    it "refuses all-bills runs when sway_locale_id is invalid" do
      expect {
        post "/bills/run_pipeline", params: {stages: ["fetch-bills"], sway_locale_id: 999_999}
      }.not_to change(LegislationPipelineRun, :count)
      expect(response).to have_http_status(:redirect)
      follow_redirect!
      expect(response.body).to include("Selected SwayLocale not found.")
    end

    it "refuses single-bill runs when sway_locale_id conflicts with bill locale" do
      bill = create(:bill, sway_locale: sway_locale)
      other_locale = create(:sway_locale, :maryland)
      expect {
        post "/bills/run_pipeline", params: {stages: ["fetch-bills"], bill_id: bill.id, sway_locale_id: other_locale.id}
      }.not_to change(LegislationPipelineRun, :count)
      expect(response).to have_http_status(:redirect)
      follow_redirect!
      expect(response.body).to include("Single-bill pipeline run cannot override bill jurisdiction with a conflicting locale.")
    end

    it "persists bill locale for single-bill runs without explicit sway_locale_id" do
      bill = create(:bill, sway_locale: sway_locale)
      expect {
        post "/bills/run_pipeline", params: {stages: ["fetch-bills"], bill_id: bill.id}
      }.to change(LegislationPipelineRun, :count).by(1)
      expect(LegislationPipelineRun.last&.sway_locale_id).to eq(sway_locale.id)
    end

    # PIPELINE_STAGE_KEYS includes summarize-bill, so a request naming it
    # is accepted, not rejected.
    it "accepts the stages param when it contains summarize-bill" do
      expect {
        post "/bills/run_pipeline", params: {stages: ["fetch-bills", "summarize-bill"], sway_locale_id: sway_locale.id}
      }.to change(LegislationPipelineRun, :count).by(1)
      expect(response).to have_http_status(:redirect)
      expect(LegislationPipelineRun.last&.stages).to contain_exactly("fetch-bills", "summarize-bill")
    end

    it "rejects when a global pipeline run is already active" do
      LegislationPipelineRun.create!(stages: ["fetch-bills"], status: "running", bill_id: nil, sway_locale: sway_locale)
      post "/bills/run_pipeline", params: {stages: ["fetch-bills"], sway_locale_id: sway_locale.id}
      expect(response).to have_http_status(:redirect)
    end

    # @lat: [[legislation-pipeline#The legislation pipeline#Runs, resume and restart#Request admission blocks every active run]]
    it "rejects a new run when a SINGLE-BILL run is already active (WR-02)" do
      bill = create(:bill)
      LegislationPipelineRun.create!(
        stages: ["fetch-bills"], status: "running", bill_id: bill.id
      )
      expect {
        post "/bills/run_pipeline", params: {stages: ["fetch-bills"], sway_locale_id: sway_locale.id}
      }.not_to change(LegislationPipelineRun, :count)
      expect(response).to have_http_status(:redirect)
      # Use flash[:alert]: the pop-up on the frontend ignores flash[:error].
      expect(flash[:alert].to_s).to match(/Pipeline already running/)
    end

    # The "requires sway admin" group earlier in this file covers the
    # admin gate. This example only checks the side effect. No run gets
    # created for a non-admin.
    it "does not create a run for a non-admin" do
      non_admin = create(:user)
      complete_registration_with_active_link(non_admin)
      sign_in non_admin
      expect {
        post "/bills/run_pipeline", params: {stages: ["fetch-bills"]}
      }.not_to change(LegislationPipelineRun, :count)
    end

    # The parameter sent over the wire is called `download_missing_assets` now. The old
    # `refresh` parameter is no longer read at all; the group further down covers what
    # happens when a caller still sends it, which is nothing.
    it "persists download_missing_assets=true when params[:download_missing_assets] is omitted" do
      post "/bills/run_pipeline", params: {stages: ["fetch-bills"], sway_locale_id: sway_locale.id}
      expect(LegislationPipelineRun.last&.download_missing_assets).to eq(true)
    end

    it "persists download_missing_assets=false when params[:download_missing_assets] is the string 'false'" do
      post "/bills/run_pipeline", params: {stages: ["fetch-bills"], sway_locale_id: sway_locale.id, download_missing_assets: "false"}
      expect(LegislationPipelineRun.last&.download_missing_assets).to eq(false)
    end

    # What happens when a second run is asked for while one is already going: a 409.
    describe "duplicate-enqueue handling" do
      let!(:existing_run) do
        LegislationPipelineRun.create!(stages: ["fetch-bills"], status: "running", bill_id: nil, sway_locale: sway_locale)
      end

      it "returns HTTP 409 with a duplicate_run envelope for mobile JSON" do
        post "/bills/run_pipeline",
          params: {stages: ["fetch-bills"], sway_locale_id: sway_locale.id},
          headers: {"Accept" => "application/json"}
        expect(response).to have_http_status(:conflict)
        body = JSON.parse(response.body)
        expect(body.dig("error", "code")).to eq("duplicate_run")
        expect(body.dig("error", "details", "existing_run_id")).to eq(existing_run.id)
      end

      it "redirects with flash[:alert] mentioning the existing run id for web Inertia" do
        post "/bills/run_pipeline", params: {stages: ["fetch-bills"], sway_locale_id: sway_locale.id}
        expect(response).to have_http_status(:redirect)
        # Use flash[:alert]: the pop-up on the frontend ignores flash[:error].
        expect(flash[:alert].to_s).to match(/Pipeline already running.*##{existing_run.id}/)
      end
    end

    # RunLegislationPipelineJob is the only pipeline job left; the older
    # StartLegislationPipelineRunJob was deleted.
    it "enqueues RunLegislationPipelineJob from controller" do
      expect {
        post "/bills/run_pipeline", params: {stages: ["fetch-bills"], sway_locale_id: sway_locale.id}
      }.to have_enqueued_job(RunLegislationPipelineJob)
    end

    # @lat: [[legislation-pipeline#The legislation pipeline#Runs, resume and restart#Request admission blocks every active run]]
    it "wraps the active-run check + create! in a requires_new transaction (WR-04)" do
      tx_calls = [] #: Array[Hash[Symbol, untyped]]
      allow(ActiveRecord::Base).to receive(:transaction).and_wrap_original do |orig, *args, **kwargs, &block|
        tx_calls << kwargs
        orig.call(*args, **kwargs, &block) # steep:ignore
      end

      post "/bills/run_pipeline", params: {stages: ["fetch-bills"], sway_locale_id: sway_locale.id}

      expect(response).to have_http_status(:redirect)
      # At least one transaction has to be opened with requires_new: true, wrapping the
      # check and the create. Others may show up too — a state machine saving after a
      # transition, for one — so this only asks that the right one is among them.
      expect(tx_calls).to include(hash_including(requires_new: true))
    end

    # @lat: [[legislation-pipeline#The legislation pipeline#Runs, resume and restart#An enqueue failure keeps the run and marks it failed]]
    it "writes a state_transition audit entry on enqueue-failure rescue (WR-03)" do
      allow(RunLegislationPipelineJob)
        .to receive(:perform_later)
        .and_raise(ActiveJob::EnqueueError, "concurrency limit hit")

      expect {
        post "/bills/run_pipeline", params: {stages: ["fetch-bills"], sway_locale_id: sway_locale.id}
      }.to change(LegislationPipelineRun, :count).by(1)
      # The row has to stay put, not be deleted, and end up marked failed.
      failed_run = LegislationPipelineRun.last
      expect(failed_run&.status).to eq("failed")
      expect(failed_run&.error_message.to_s).to match(/enqueue failed/)
      # The state-machine after_transition writes the audit-log row.
      entries = PipelineActivityLogEntry.where(
        subject_type: "LegislationPipelineRun",
        subject_id: failed_run&.id.to_s,
        event_type: "state_transition"
      )
      expect(entries.count).to be >= 1
      expect(entries.last&.payload&.dig("to")).to eq("failed")
    end
  end

  # @lat: [[legislation-pipeline#The legislation pipeline#Runs, resume and restart#Requests selecting both fetch stages force asset downloads]]
  describe "POST /bills/run_pipeline — download_missing_assets contract" do
    it "force-computes dma=true on URL-handcrafted POST with both fetches checked + download_missing_assets=0 (backend-enforced)" do
      post "/bills/run_pipeline",
        params: {stages: ["fetch-bills", "fetch-hearings", "summarize-bill"], sway_locale_id: sway_locale.id, download_missing_assets: "0"}
      expect(response).to have_http_status(:redirect)
      expect(LegislationPipelineRun.last&.download_missing_assets).to eq(true)
    end

    it "persists dma=false when only one fetch stage is selected (force-compute does not trigger)" do
      post "/bills/run_pipeline",
        params: {stages: ["extract-text"], sway_locale_id: sway_locale.id, download_missing_assets: "0"}
      expect(response).to have_http_status(:redirect)
      expect(LegislationPipelineRun.last&.download_missing_assets).to eq(false)
    end

    it "accepts summarize-bill as a selected stage" do
      expect {
        post "/bills/run_pipeline", params: {stages: ["summarize-bill"], sway_locale_id: sway_locale.id}
      }.to change(LegislationPipelineRun, :count).by(1)
      expect(response).to have_http_status(:redirect)
      expect(LegislationPipelineRun.last&.stages).to include("summarize-bill")
    end

    it "accepts fetch-law as a selected stage (added to PIPELINE_STAGE_KEYS)" do
      expect {
        post "/bills/run_pipeline", params: {stages: ["fetch-law"], sway_locale_id: sway_locale.id}
      }.to change(LegislationPipelineRun, :count).by(1)
      expect(response).to have_http_status(:redirect)
      expect(LegislationPipelineRun.last&.stages).to include("fetch-law")
    end

    it "drops bogus stages via the allowlist filter" do
      expect {
        post "/bills/run_pipeline", params: {stages: ["fetch-bills", "bogus-stage"], sway_locale_id: sway_locale.id}
      }.to change(LegislationPipelineRun, :count).by(1)
      # An unrecognised stage name is quietly dropped, so the run is still created,
      # with whichever names were valid.
      expect(LegislationPipelineRun.last&.stages).not_to include("bogus-stage")
    end

    it "ignores legacy params[:refresh] without raising (back-compat)" do
      expect {
        post "/bills/run_pipeline", params: {stages: ["fetch-bills"], sway_locale_id: sway_locale.id, refresh: "1"}
      }.to change(LegislationPipelineRun, :count).by(1)
      expect(response).to have_http_status(:redirect)
      # With refresh sent and download_missing_assets absent, the new field falls back
      # to true, and refresh is ignored.
      expect(LegislationPipelineRun.last&.download_missing_assets).to eq(true)
    end

    # @lat: [[admin-hub-and-tabs#The admin hub and the Bill Creator's tabs#Each Bill Creator tab has its own path]]
    it "redirects to new_bill_creator_path when no :id param is supplied (WR-11)" do
      # Seed a pre-existing bill — would be picked up by Bill.first.
      create(:bill)
      post "/bills/run_pipeline", params: {stages: ["fetch-bills"], sway_locale_id: sway_locale.id}
      expect(response).to have_http_status(:redirect)
      expect(response.location).to include(new_bill_creator_path(bill_creator_tab: :pipeline))
    end

    # @lat: [[admin-hub-and-tabs#The admin hub and the Bill Creator's tabs#Each Bill Creator tab has its own path]]
    it "redirects to edit_bill_creator_path when bill_id param is supplied via body (UAT-3)" do
      bill = create(:bill)
      post "/bills/run_pipeline", params: {stages: ["fetch-bills"], bill_id: bill.id}
      expect(response).to have_http_status(:redirect)
      expect(response.location).to include(pipeline_bill_creator_path(id: bill.id))
      # The other half of the check: it must not land on the all-bills page.
      expect(response.location).not_to include(new_bill_creator_path(bill_creator_tab: :pipeline))
    end

    describe "POST /bills/legislation_pipeline_runs/:id/restart" do
      let(:bill) { create(:bill) }
      let(:parent_run) do
        LegislationPipelineRun.create!(
          stages: ["fetch-bills"],
          status: "failed",
          bill: bill,
          download_missing_assets: true
        )
      end

      it "applies download_missing_assets=false override on the child run" do
        existing_parent = parent_run
        expect {
          post "/bills/legislation_pipeline_runs/#{existing_parent.id}/restart",
            params: {download_missing_assets: "0"}
        }.to change(LegislationPipelineRun, :count).by(1)
        child = LegislationPipelineRun.where(parent_run_id: existing_parent.id.to_s).last
        expect(child&.download_missing_assets).to eq(false)
      end

      it "inherits parent dma when no download_missing_assets param is supplied (default)" do
        parent_run.update!(download_missing_assets: false)
        existing_parent = parent_run
        expect {
          post "/bills/legislation_pipeline_runs/#{existing_parent.id}/restart"
        }.to change(LegislationPipelineRun, :count).by(1)
        child = LegislationPipelineRun.where(parent_run_id: existing_parent.id.to_s).last
        expect(child&.download_missing_assets).to eq(false)
      end
    end
  end

  # @lat: [[legislation-pipeline#The legislation pipeline#Runs, resume and restart]]
  describe "POST /bills/legislation_pipeline_runs/:id/resume" do
    let(:bill) { create(:bill) }

    it "enqueues a child run and flashes the queued notice for a failed single-bill run" do
      parent = LegislationPipelineRun.create!(stages: ["fetch-bills"], status: "failed", bill: bill)

      expect {
        post "/bills/legislation_pipeline_runs/#{parent.id}/resume"
      }.to change(LegislationPipelineRun, :count).by(1)

      child = LegislationPipelineRun.where(parent_run_id: parent.id.to_s).last!
      expect(child&.origin).to eq("resume")
      expect(response).to have_http_status(:redirect)
      expect(flash[:notice]).to match(/Resume queued \(run #{child.id}\)/)
    end

    # ResumeNotAllowed is raised before the service creates any row, so the shared
    # helper's rescue — the one covering both a bad stage name and a refused resume —
    # has to turn it into an error on the page, leaving no stray child run behind.
    it "surfaces ResumeNotAllowed as an inertia error without creating a child" do
      parent = LegislationPipelineRun.create!(stages: ["fetch-bills"], status: "succeeded", bill: bill)

      expect {
        post "/bills/legislation_pipeline_runs/#{parent.id}/resume"
      }.not_to change(LegislationPipelineRun, :count)

      expect(response).to have_http_status(:redirect)
      expect(session[:inertia_errors].to_h.symbolize_keys).to include(:pipeline)
    end
  end

  describe "pipeline starts for a bearer request" do
    let(:bearer_headers) { authenticate_as(admin).merge("Accept" => "application/json") }
    let(:bill) { create(:bill, sway_locale: sway_locale) }

    # @lat: [[mobile-bill-creator#Sections#The pipeline stages section]]
    it "queues a run and answers 200 JSON with no redirect" do
      expect {
        post "/bills/run_pipeline",
          params: {stages: ["fetch-bills", "extract-text"], bill_id: bill.id, download_missing_assets: false},
          headers: bearer_headers
      }.to change(LegislationPipelineRun, :count).by(1)

      expect(response).to have_http_status(:ok)
      expect(response.media_type).to eq("application/json")
      run = LegislationPipelineRun.last!
      expect(run.stages).to eq(["fetch-bills", "extract-text"])
      expect(run.download_missing_assets).to eq(false)
    end

    # @lat: [[mobile-bill-creator#Sections#The pipeline stages section]]
    it "answers a refused run with 422 JSON naming the pipeline error" do
      expect {
        post "/bills/run_pipeline", params: {stages: ["fetch-bills"]}, headers: bearer_headers
      }.not_to change(LegislationPipelineRun, :count)

      expect(response).to have_http_status(:unprocessable_content)
      expect(json_body.dig(:error, :code)).to eq("validation_failed")
      expect(json_body.dig(:error, :details, :pipeline)).to eq("A SwayLocale is required for all-bills pipeline runs.")
    end

    # @lat: [[mobile-bill-creator#Sections#The pipeline stages section]]
    it "answers a duplicate run with 409 duplicate_run" do
      existing = LegislationPipelineRun.create!(stages: ["fetch-bills"], status: "running", sway_locale: sway_locale)

      post "/bills/run_pipeline", params: {stages: ["fetch-bills"], bill_id: bill.id}, headers: bearer_headers

      expect(response).to have_http_status(:conflict)
      expect(json_body.dig(:error, :code)).to eq("duplicate_run")
      expect(json_body.dig(:error, :details, :existing_run_id)).to eq(existing.id)
    end

    # @lat: [[mobile-bill-creator#Sections#The pipeline stages section]]
    it "resumes a failed run and answers 200 JSON" do
      parent = LegislationPipelineRun.create!(stages: ["fetch-bills"], status: "failed", bill: bill)

      expect {
        post "/bills/legislation_pipeline_runs/#{parent.id}/resume", headers: bearer_headers
      }.to change(LegislationPipelineRun, :count).by(1)

      expect(response).to have_http_status(:ok)
      expect(response.media_type).to eq("application/json")
    end

    # @lat: [[mobile-bill-creator#Sections#The pipeline stages section]]
    it "answers a refused resume with 422 JSON" do
      parent = LegislationPipelineRun.create!(stages: ["fetch-bills"], status: "succeeded", bill: bill)

      post "/bills/legislation_pipeline_runs/#{parent.id}/resume", headers: bearer_headers

      expect(response).to have_http_status(:unprocessable_content)
      expect(json_body.dig(:error, :details, :pipeline)).to be_present
    end

    # @lat: [[mobile-bill-creator#Sections#The pipeline stages section]]
    it "restarts a failed run and answers 200 JSON" do
      parent = LegislationPipelineRun.create!(stages: ["fetch-bills"], status: "failed", bill: bill)

      expect {
        post "/bills/legislation_pipeline_runs/#{parent.id}/restart", headers: bearer_headers
      }.to change(LegislationPipelineRun, :count).by(1)

      expect(response).to have_http_status(:ok)
      expect(response.media_type).to eq("application/json")
    end
  end

  describe "pipeline starts for a web request" do
    let(:bill) { create(:bill, sway_locale: sway_locale) }

    it "redirects a queued run to the pipeline tab with the queued notice" do
      post "/bills/run_pipeline", params: {stages: ["fetch-bills"], bill_id: bill.id}

      run = LegislationPipelineRun.last!
      expect(response).to have_http_status(:found)
      expect(URI.parse(response.location).path).to eq(pipeline_bill_creator_path(id: bill.id))
      expect(flash[:notice]).to eq("Pipeline run #{run.id} queued (1 stages)")
      expect(flash[:alert]).to be_nil
    end

    it "redirects a refused run with the pipeline error and no flash" do
      post "/bills/run_pipeline", params: {stages: ["fetch-bills"]}

      expect(response).to have_http_status(:found)
      expect(session[:inertia_errors].to_h.symbolize_keys).to eq(pipeline: "A SwayLocale is required for all-bills pipeline runs.")
      expect(flash[:notice]).to be_nil
      expect(flash[:alert]).to be_nil
    end
  end

  describe "POST /bills/sweep_stale_pipeline_runs" do
    before do
      allow(LegislationPipelineRun).to receive(:solid_queue_job_exists_for?).and_return(false)
    end

    # @lat: [[legislation-pipeline#The legislation pipeline#Runs, resume and restart#Stuck runs require evidence of abandonment]]
    it "marks abandoned queued/running rows as failed and keeps their history" do
      a = LegislationPipelineRun.create!(stages: ["fetch-bills"], status: "queued", updated_at: 5.hours.ago)
      b = LegislationPipelineRun.create!(stages: ["fetch-bills"], status: "running", updated_at: 5.hours.ago)
      LegislationPipelineRun.create!(stages: ["fetch-bills"], status: "completed")

      post sweep_stale_pipeline_runs_bills_path

      expect(response).to have_http_status(:redirect)
      expect(a.reload.status).to eq("failed")
      expect(b.reload.status).to eq("failed")
    end

    it "marks runs stuck in per-stage states as failed" do
      stuck_runs = LegislationPipelineRun::PHASE_52_STAGE_STATES.map do |stage_state|
        LegislationPipelineRun.create!(stages: ["fetch-bills"], status: stage_state.to_s, updated_at: 5.hours.ago)
      end

      post sweep_stale_pipeline_runs_bills_path

      expect(response).to have_http_status(:redirect)
      stuck_runs.each do |run|
        expect(run.reload.status).to eq("failed"),
          "expected run with stage state #{run.status_was} to be swept to failed"
      end
    end

    it "leaves terminal runs (succeeded, completed, partial, failed, cancelled) untouched" do
      terminal_statuses = %w[succeeded completed partial failed cancelled]
      runs = terminal_statuses.map do |s|
        LegislationPipelineRun.create!(stages: ["fetch-bills"], status: s)
      end

      post sweep_stale_pipeline_runs_bills_path

      runs.zip(terminal_statuses).each do |run, status|
        expect(run.reload.status).to eq(status), "terminal #{status} run was swept"
      end
    end

    it "preserves fresh runs and old runs whose background job still exists" do
      fresh = create(:legislation_pipeline_run, status: "queued")
      progressing = create(:legislation_pipeline_run, status: "fetching_law", created_at: 1.day.ago)
      owned = create(:legislation_pipeline_run, status: "running", updated_at: 5.hours.ago)
      allow(LegislationPipelineRun).to receive(:solid_queue_job_exists_for?).with(owned).and_return(true)

      post sweep_stale_pipeline_runs_bills_path

      expect(response).to have_http_status(:redirect)
      expect(fresh.reload.status).to eq("queued")
      expect(progressing.reload.status).to eq("fetching_law")
      expect(owned.reload.status).to eq("running")
      expect(owned.error_message).to be_nil
    end

    it "preserves a live summary batch while closing an expired batch wait" do
      live = create(:legislation_pipeline_run, status: "awaiting_summary_batch", updated_at: 5.hours.ago)
      create(:pipeline_run_summary_batch, legislation_pipeline_run: live)
      expired = create(:legislation_pipeline_run, status: "awaiting_summary_batch", updated_at: 5.hours.ago)
      create(:pipeline_run_summary_batch, :expired, legislation_pipeline_run: expired)

      post sweep_stale_pipeline_runs_bills_path

      expect(live.reload.status).to eq("awaiting_summary_batch")
      expect(expired.reload.status).to eq("failed")
    end

    # @lat: [[mobile-bill-creator#Sections#The pipeline cleanup section]]
    it "answers a bearer client with 200 and the number of runs it failed" do
      stuck = LegislationPipelineRun.create!(stages: ["fetch-bills"], status: "running", updated_at: 5.hours.ago)
      LegislationPipelineRun.create!(stages: ["fetch-bills"], status: "queued")

      post sweep_stale_pipeline_runs_bills_path, headers: authenticate_as(admin).merge("Accept" => "application/json")

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body).to eq("count" => 1)
      expect(stuck.reload.status).to eq("failed")
    end

    # The "requires sway admin" group earlier in this file covers the
    # admin gate. This example only checks the side effect. The run's
    # status does not change for a non-admin.
    it "leaves the run status untouched for a non-admin" do
      run = LegislationPipelineRun.create!(stages: ["fetch-bills"], status: "running")
      non_admin = create(:user)
      complete_registration_with_active_link(non_admin)
      sign_in non_admin
      post sweep_stale_pipeline_runs_bills_path
      expect(run.reload.status).to eq("running")
    end

    # The same rule as starting a run. The fallback used to be
    # `params[:id].presence || Bill.first&.id`; picking an arbitrary bill is gone, and
    # with no :id the redirect goes to new_bill_creator_path.
    it "redirects to new_bill_creator_path when no :id param is supplied (WR-11)" do
      create(:bill)
      post sweep_stale_pipeline_runs_bills_path
      expect(response).to have_http_status(:redirect)
      expect(response.location).to include(new_bill_creator_path(bill_creator_tab: :pipeline))
      follow_redirect!
      expect(inertia).to render_component(Pages::BILL_CREATOR)
      expect(inertia.props[:tab_key]).to eq("pipeline")
    end
  end

  # @lat: [[legislation-pipeline#The legislation pipeline#Runs, resume and restart#Bill refresh uses every active status]]
  describe "GET /admin/bill_creator/:id — bill_pipeline_refresh" do
    let(:bill) { create(:bill) }

    it "reports the run while it sits in a per-stage state" do
      LegislationPipelineRun::PHASE_52_STAGE_STATES.each do |state|
        run = create(:legislation_pipeline_run, bill: bill, status: state.to_s)

        get "/admin/bill_creator/#{bill.id}/creator"

        expect(inertia).to render_component(Pages::BILL_CREATOR)

        refresh = inertia.props[:bill][:bill_pipeline_refresh]
        expect(refresh).to be_present, "expected a #{state} run to be reported as in flight"
        expect(refresh[:id]).to eq(run.id)
        run.destroy!
      end
    end

    it "reports nothing once the run reaches a terminal state" do
      create(:legislation_pipeline_run, bill: bill, status: "completed")

      get "/admin/bill_creator/#{bill.id}/creator"

      expect(inertia).to render_component(Pages::BILL_CREATOR)
      expect(inertia.props[:bill][:bill_pipeline_refresh]).to be_nil
    end
  end
end
