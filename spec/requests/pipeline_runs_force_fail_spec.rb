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
