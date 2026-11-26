# frozen_string_literal: true

require "rails_helper"

# The admin-only force_fail action on PipelineRunsController.
RSpec.describe "PipelineRunsForceFail", type: :request do
  include_context "SessionDouble"

  let!(:run) { create(:legislation_pipeline_run, :running) }

  include_examples "requires sway admin",
    verb: :post,
    path: "/pipeline_runs/0/force_fail",
    params: {confirm_phrase: "force fail"}

  context "as admin" do
    let(:admin) { create(:user, :sway_admin) }

    before { session_hash[:user_id] = admin.id }

    it "transitions run to failed + writes force_fail_triggered log on confirmed phrase" do
      post "/pipeline_runs/#{run.id}/force_fail", params: {confirm_phrase: "force fail"}
      expect(run.reload.status).to eq("failed")
      expect(PipelineActivityLogEntry.where(event_type: "force_fail_triggered").count).to eq(1)
    end

    it "rejects when confirm_phrase mismatch" do
      post "/pipeline_runs/#{run.id}/force_fail", params: {confirm_phrase: "wrong"}
      expect(run.reload.status).to eq("running")
      expect(PipelineActivityLogEntry.where(event_type: "force_fail_triggered").count).to eq(0)
    end

    it "rejects when run not in-flight" do
      run.update_column(:status, "completed")
      post "/pipeline_runs/#{run.id}/force_fail", params: {confirm_phrase: "force fail"}
      expect(run.reload.status).to eq("completed")
      expect(PipelineActivityLogEntry.where(event_type: "force_fail_triggered").count).to eq(0)
    end

    it "redirects a wrong phrase back with the pipeline error for the web" do
      post "/pipeline_runs/#{run.id}/force_fail", params: {confirm_phrase: "wrong"}
      expect(response).to redirect_to(pipeline_runs_path)
    end

    context "for a bearer client" do
      let(:bearer_headers) { authenticate_as(admin).merge("Accept" => "application/json") }

      # @lat: [[mobile-bill-creator#Sections#The pipeline cleanup section]]
      it "force fails the run and answers 200 with the failed run's summary" do
        post "/pipeline_runs/#{run.id}/force_fail", params: {confirm_phrase: "force fail"}, headers: bearer_headers

        expect(response).to have_http_status(:ok)
        expect(response.parsed_body.fetch("run")).to include("id" => run.id, "status" => "failed")
        expect(run.reload.status).to eq("failed")
      end

      # @lat: [[mobile-bill-creator#Sections#The pipeline cleanup section]]
      it "answers a wrong phrase with 422 and the pipeline error under details" do
        post "/pipeline_runs/#{run.id}/force_fail", params: {confirm_phrase: "wrong"}, headers: bearer_headers

        expect(response).to have_http_status(:unprocessable_content)
        expect(response.parsed_body.dig("error", "code")).to eq("validation_failed")
        expect(response.parsed_body.dig("error", "details", "pipeline")).to eq("Confirmation phrase mismatch")
        expect(run.reload.status).to eq("running")
      end

      # @lat: [[mobile-bill-creator#Sections#The pipeline cleanup section]]
      it "answers a run that is not in flight with 422" do
        run.update_column(:status, "completed")

        post "/pipeline_runs/#{run.id}/force_fail", params: {confirm_phrase: "force fail"}, headers: bearer_headers

        expect(response).to have_http_status(:unprocessable_content)
        expect(response.parsed_body.dig("error", "details", "pipeline")).to eq(
          "Run ##{run.id} is not in-flight (status: completed)"
        )
      end
    end

    # @lat: [[legislation-pipeline#The legislation pipeline#Runs, resume and restart#The admin surface is index-only#Force-fail returns to the working surface]]
    context "with back_to=bill_creator" do
      it "redirects to new_bill_creator_path(bill_creator_tab: :pipeline) for a global run (bill_id nil)" do
        expect(run.bill_id).to be_nil
        post "/pipeline_runs/#{run.id}/force_fail",
          params: {confirm_phrase: "force fail", back_to: "bill_creator"}
        expect(response).to redirect_to(new_bill_creator_path(bill_creator_tab: :pipeline))
      end

      it "still uses the bill pipeline tab redirect when the run is bill-scoped (back_to ignored if bill_id present)" do
        bill_id_run = create(:legislation_pipeline_run, :running, bill_id: create(:bill).id)
        post "/pipeline_runs/#{bill_id_run.id}/force_fail",
          params: {confirm_phrase: "force fail", back_to: "bill_creator"}
        expect(response).to redirect_to(pipeline_bill_creator_path(id: bill_id_run.bill_id))
      end
    end
  end
end
