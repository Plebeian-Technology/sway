require "rails_helper"

# @lat: [[bills-controller-design#Why the pipeline-run concurrency spec dropped its second run blocked example]]
RSpec.describe BillsController, type: :controller do
  include_context "SessionDouble"

  # Helper: pull the errors out of redirect_to(path, inertia: {errors: ...}).
  # On a redirect, inertia_rails puts them in session[:inertia_errors], not flash.
  def inertia_errors
    err = session[:inertia_errors] || {}
    err.transform_keys(&:to_sym)
  end

  # Helper: pull out the props merged in by inertia_share blocks. inertia.props
  # holds both the props passed to render and the shared ones.
  def inertia_share_props
    inertia&.props&.to_h&.symbolize_keys || {}
  end

  before do
    admin = create(:user, :sway_admin)
    sign_in(admin)
  end

  it "shares legislation_pipeline_run prop on every BillCreator action via inertia_share" do
    # Once the concern is included, every Inertia response from BillsController
    # has to carry the legislation_pipeline_run prop — nil when no run is
    # active, a hash when one is. The LegislationPipelineRunSourcing concern
    # supplies it via inertia_share { legislation_pipeline_run_props }.
    bill = create(:bill)
    get :edit, params: {id: bill.id}
    shared = inertia_share_props
    expect(shared).to have_key(:legislation_pipeline_run)
  end

  # The inertia_share block only runs for admins (current_user&.is_sway_admin?).
  # Everyone else must not get the legislation_pipeline_run prop: it leaks
  # information, and it costs 2 extra database queries on every public bill page.
  context "when user is not a sway admin" do
    before do
      non_admin = create(:user)
      sign_in(non_admin)
    end

    it "does NOT share legislation_pipeline_run prop to non-admin users" do
      bill = create(:bill)
      get :show, params: {id: bill.id}
      shared = inertia_share_props
      expect(shared).not_to have_key(:legislation_pipeline_run)
    end
  end

  context "when user is unauthenticated" do
    before do
      # Undo the admin sign_in from the outer block. With session_hash empty,
      # current_user is nil and the admin check withholds the prop.
      session_hash.clear
    end

    it "does NOT share legislation_pipeline_run prop to anonymous requests" do
      bill = create(:bill)
      get :show, params: {id: bill.id}
      shared = inertia_share_props
      expect(shared).not_to have_key(:legislation_pipeline_run)
    end
  end

  # @lat: [[legislation-pipeline#The legislation pipeline#Runs, resume and restart#Which run the Bill Creator surfaces]]
  describe "surfaced run selection" do
    it "surfaces the newest run even when it succeeded, not the older failed run" do
      LegislationPipelineRun.create!(stages: ["fetch_bills"], status: "failed", error_message: "boom")
      newest = LegislationPipelineRun.create!(stages: ["fetch_bills"], status: "succeeded")

      get :new

      run = inertia_share_props[:legislation_pipeline_run]
      expect(run).to be_present
      expect(run["id"]).to eq(newest.id)
      expect(run["status"]).to eq("succeeded")
    end

    it "pins the run named by ?run_id=, overriding default surfacing" do
      pinned = LegislationPipelineRun.create!(stages: ["fetch_bills"], status: "failed", error_message: "boom")
      LegislationPipelineRun.create!(stages: ["fetch_bills"], status: "succeeded")

      get :new, params: {run_id: pinned.id}

      run = inertia_share_props[:legislation_pipeline_run]
      expect(run["id"]).to eq(pinned.id)
      expect(run["status"]).to eq("failed")
    end

    # @lat: [[pipeline-run-pin-vs-active-run#Why the pinned run and the active run are two different props]]
    it "does not let a pinned ?run_id= redirect active_legislation_pipeline_run" do
      finished_pin = LegislationPipelineRun.create!(stages: ["fetch_bills"], status: "succeeded")
      running = LegislationPipelineRun.create!(stages: ["fetch_bills"], status: "running")

      get :new, params: {run_id: finished_pin.id}

      pinned_run = inertia_share_props[:legislation_pipeline_run]
      active_run = inertia_share_props[:active_legislation_pipeline_run]

      expect(pinned_run["id"]).to eq(finished_pin.id)
      expect(active_run["id"]).to eq(running.id)
      expect(active_run["status"]).to eq("running")
    end

    it "leaves active_legislation_pipeline_run nil when nothing is running, pin or no pin" do
      finished_pin = LegislationPipelineRun.create!(stages: ["fetch_bills"], status: "succeeded")

      get :new, params: {run_id: finished_pin.id}

      expect(inertia_share_props[:legislation_pipeline_run]["id"]).to eq(finished_pin.id)
      expect(inertia_share_props[:active_legislation_pipeline_run]).to be_nil
    end

    it "exposes recent_pipeline_runs for the run-selector dropdown" do
      LegislationPipelineRun.create!(stages: ["fetch_bills"], status: "failed", error_message: "boom")
      LegislationPipelineRun.create!(stages: ["fetch_bills"], status: "succeeded")

      get :new

      recent = inertia_share_props[:recent_pipeline_runs]
      expect(recent).to be_an(Array)
      expect(recent.size).to eq(2)
    end
  end

  # @lat: [[legislation-pipeline#The legislation pipeline#Runs, resume and restart#Which run the Bill Creator surfaces]]
  describe "#new activity log" do
    it "ships activity_log_entries on the All-bills view" do
      get :new

      expect(inertia_share_props).to have_key(:activity_log_entries)
    end
  end
end
