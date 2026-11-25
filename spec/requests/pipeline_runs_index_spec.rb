# frozen_string_literal: true

require "rails_helper"

# The /pipeline_runs index page sends what RunSummarySerializer produces, not
# the raw `.map(&:attributes)` dump it used to send.
RSpec.describe "PipelineRunsIndex", type: :request do
  include_context "SessionDouble"

  include_examples "requires sway admin",
    verb: :get,
    path: "/pipeline_runs"

  context "as admin" do
    let(:admin) { create(:user, :sway_admin) }
    before { session_hash[:user_id] = admin.id }

    let!(:run) do
      create(:legislation_pipeline_run, :completed,
        started_at: Time.utc(2026, 5, 13, 10, 0, 0),
        completed_at: Time.utc(2026, 5, 13, 10, 25, 0))
    end

    it "renders the admin/PipelineRuns/Index Inertia page" do
      get "/pipeline_runs"
      expect(response).to have_http_status(:ok)
      expect(inertia).to be_inertia_response
      expect(inertia).to render_component("admin/PipelineRuns/Index")
    end

    it "ships the RunSummarySerializer row shape (not raw attributes)" do
      get "/pipeline_runs"

      runs = inertia.props[:runs]
      expect(runs).to be_an(Array)
      expect(runs.length).to eq(1)

      # Every key PipelineRuns::RunSummarySerializer produces must survive the
      # trip into the Inertia prop. That trip goes through JSON, which turns
      # symbol keys into strings, so convert them before comparing.
      row = runs.first
      expect(row.keys.map(&:to_s)).to match_array(
        %w[id status kind bill_id bill_external_id remote_run_id started_at completed_at current_stage bills_total bills_succeeded bills_failed failing_stage]
      )
      expect(row[:id] || row["id"]).to eq(run.id)
    end

    # @lat: [[pipeline-runs-index-serializer-whitelist#Why /pipeline_runs' rows go through a whitelisting serializer]]
    it "does not leak DB-internal columns the old .map(&:attributes) dump exposed" do
      get "/pipeline_runs"
      row = inertia.props[:runs].first
      raw_keys = row.keys.map(&:to_s)
      expect(raw_keys).not_to include("error_message", "parent_run_id", "cached_full_breakdown")
    end
  end

  context "with a bearer token and Accept: application/json" do
    let(:api_token) { SecureRandom.hex(32) }
    let(:headers) { {"Authorization" => "Bearer #{api_token}", "Accept" => "application/json"} }

    # @lat: [[mobile-admin-area#The pipeline runs screen]]
    it "serves the run summaries as JSON to a sway admin" do
      ApiKey.create!(bearer: create(:user, :sway_admin), token: api_token)
      run = create(:legislation_pipeline_run, :completed)

      get "/pipeline_runs", headers: headers

      expect(response).to have_http_status(:ok)
      expect(response.media_type).to eq("application/json")
      row = response.parsed_body.fetch("runs").sole
      expect(row).to include("id" => run.id, "status" => run.status, "kind" => "all_bills")
    end

    it "refuses a non-admin with a forbidden JSON error" do
      user = create(:user)
      create(:user_legislator, user: user)
      user.complete!
      ApiKey.create!(bearer: user, token: api_token)

      get "/pipeline_runs", headers: headers

      expect(response).to have_http_status(:forbidden)
      expect(response.parsed_body.dig("error", "code")).to eq("forbidden")
    end
  end
end
