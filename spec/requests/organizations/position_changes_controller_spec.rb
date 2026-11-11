# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Organizations::PositionChangesController", type: :request do
  include_context "SessionDouble"
  include_context "Setup"

  describe "org-admin gate" do
    include_examples "requires organization admin",
      verb: :patch,
      path: -> {
        bill = create(:bill)
        position = create(:organization_bill_position, organization: organization, bill: bill)
        position_change = create(:organization_bill_position_change,
          organization_bill_position: position)
        "/organizations/#{organization.id}/position_changes/#{position_change.id}"
      },
      params: {position_change: {status: "approved"}}
  end

  # @lat: [[organization-position-change-controller#Organization position-change responses#Finalized changes receive the same refusal message]]
  describe "PATCH /organizations/:organization_id/position_changes/:id (approve, WR-08)" do
    let(:approve_organization) { create(:organization) }
    let(:approve_admin) { create(:user).tap { |u| complete_registration_with_active_link(u) } }
    let(:approve_position) { create(:organization_bill_position, organization: approve_organization) }
    let(:approve_change) do
      create(:organization_bill_position_change,
        organization_bill_position: approve_position,
        updated_by: approve_admin,
        status: :pending)
    end

    before do
      create(:user_organization_membership, :admin, user: approve_admin, organization: approve_organization)
    end

    let(:approve_path) { "/organizations/#{approve_organization.id}/position_changes/#{approve_change.id}" }

    def make_approved!(record, by_user)
      record.update!(approved_by: by_user, status: :approved)
    end

    def make_rejected!(record, by_user)
      record.update!(rejected_by: by_user, rejected_at: Time.current, status: :rejected)
    end

    context "HTML / cookie auth (web)" do
      it "redirects with flash[:alert] when an admin tries to approve a row that was already rejected" do
        make_rejected!(approve_change, approve_admin)
        sign_in(approve_admin)
        patch approve_path
        expect(response).to have_http_status(:found)
        expect(flash[:alert]).to eq(Organizations::PositionChangesController::ALREADY_FINALIZED_MESSAGE)
        # Critical assertion: rejected row was NOT re-approved.
        approve_change.reload
        expect(approve_change.status).to eq("rejected")
        expect(approve_change.approved_by_id).to be_nil
        expect(approve_change.rejected_by_id).to eq(approve_admin.id)
      end

      it "redirects with flash[:alert] when an admin tries to re-approve a row that was already approved" do
        make_approved!(approve_change, approve_admin)
        sign_in(approve_admin)
        patch approve_path
        expect(response).to have_http_status(:found)
        expect(flash[:alert]).to eq(Organizations::PositionChangesController::ALREADY_FINALIZED_MESSAGE)
        expect(approve_change.reload.status).to eq("approved") # unchanged
      end
    end

    context "JSON / bearer auth (mobile)" do
      it "returns 422 with literal { error: 'Change is already finalized.' } when already rejected" do
        make_rejected!(approve_change, approve_admin)
        patch approve_path,
          headers: authenticate_as(approve_admin).merge("Accept" => "application/json")
        expect(response).to have_http_status(:unprocessable_content)
        body = JSON.parse(response.body)
        expect(body["error"]["code"]).to eq("already_finalized")
        expect(body["error"]["message"]).to eq(Organizations::PositionChangesController::ALREADY_FINALIZED_MESSAGE)
        approve_change.reload
        expect(approve_change.status).to eq("rejected")
        expect(approve_change.approved_by_id).to be_nil
      end

      it "returns 422 with literal { error: 'Change is already finalized.' } when already approved" do
        make_approved!(approve_change, approve_admin)
        patch approve_path,
          headers: authenticate_as(approve_admin).merge("Accept" => "application/json")
        expect(response).to have_http_status(:unprocessable_content)
        body = JSON.parse(response.body)
        expect(body["error"]["code"]).to eq("already_finalized")
        expect(body["error"]["message"]).to eq(Organizations::PositionChangesController::ALREADY_FINALIZED_MESSAGE)
        expect(approve_change.reload.status).to eq("approved")
      end

      # Pin the 204 mobile callers get on success, matching what #destroy
      # returns them. Without this, a refactor that dropped the
      # mobile_api_request? branch from #update's success path would start
      # redirecting mobile callers to an Inertia URL their parser cannot read.
      it "returns 204 No Content on mobile approve success of a pending row" do
        patch approve_path,
          headers: authenticate_as(approve_admin).merge("Accept" => "application/json")
        expect(response).to have_http_status(:no_content)
        expect(response.body).to be_empty
        approve_change.reload
        expect(approve_change.status).to eq("approved")
        expect(approve_change.approved_by_id).to eq(approve_admin.id)
      end
    end
  end

  # The behavior comes from ApplicationController#authenticate_sway_user! and
  # Organizations::BaseController#verify_is_organization_admin!.
  # @lat: [[admin-gate-shared-examples#Admin-gate shared examples#The admin trait replaces the configured phone list]]
  # @lat: [[organization-position-change-controller#Organization position-change responses#The final-state helpers keep examples on one rule]]
  describe "DELETE /organizations/:organization_id/position_changes/:id" do
    let(:delete_organization) { create(:organization) }
    let(:delete_admin) { create(:user).tap { |u| complete_registration_with_active_link(u) } }
    let(:delete_non_admin_member) { create(:user).tap { |u| complete_registration_with_active_link(u) } }
    let(:delete_position) { create(:organization_bill_position, organization: delete_organization) }
    let(:delete_change) do
      create(:organization_bill_position_change,
        organization_bill_position: delete_position,
        updated_by: delete_admin,
        status: :pending)
    end

    before do
      # Use the :admin factory trait, not `role: :admin`
      create(:user_organization_membership, :admin, user: delete_admin, organization: delete_organization)
      create(:user_organization_membership, user: delete_non_admin_member, organization: delete_organization)
    end

    let(:delete_path) { "/organizations/#{delete_organization.id}/position_changes/#{delete_change.id}" }

    # Helpers that set a row's final state, so the rule lives in one place.
    def make_approved!(record, by_user)
      record.update!(approved_by: by_user, status: :approved)
    end

    def make_rejected!(record, by_user)
      record.update!(rejected_by: by_user, rejected_at: Time.current, status: :rejected)
    end

    context "HTML / cookie auth (web)" do
      it "redirects unauthenticated callers to root and leaves the row pending" do
        # The HTML branch of authenticate_sway_user! redirects to root_url
        delete delete_path
        expect(response).to have_http_status(:found)
        expect(response).to redirect_to(root_url)
        expect(delete_change.reload.status).to eq("pending")
      end

      it "302s with flash[:alert]='Forbidden' for a non-admin org member" do
        # The `else` branch of verify_is_organization_admin!: a member, but not an admin
        sign_in(delete_non_admin_member)
        delete delete_path
        expect(response).to have_http_status(:found)
        expect(flash[:alert]).to eq("Forbidden")
        expect(delete_change.reload.status).to eq("pending")
      end

      it "renders 403 plain 'Forbidden' for a sway admin who is not an org member" do
        # The `current_user_membership.nil?` branch of verify_is_organization_admin!
        # Built with the :sway_admin trait; there is no is_sway_admin column
        sway_admin = create(:user, :sway_admin)
        sign_in(sway_admin)
        delete delete_path
        expect(response).to have_http_status(:forbidden)
        expect(response.body).to eq("Forbidden")
        expect(delete_change.reload.status).to eq("pending")
      end

      it "soft-rejects on success (admin) and redirects with flash[:notice]" do
        sign_in(delete_admin)
        expect {
          delete delete_path
        }.to change { delete_change.reload.status }.from("pending").to("rejected")

        expect(delete_change.rejected_by_id).to eq(delete_admin.id)
        expect(delete_change.rejected_at).to be_present
        expect(response).to have_http_status(:found)
        expect(flash[:notice]).to eq("Change rejected.")
      end

      it "redirects with flash[:alert] when the change is already approved (W7 helper)" do
        make_approved!(delete_change, delete_admin)
        sign_in(delete_admin)
        delete delete_path
        # On the web this refusal takes its own branch: flash[:alert] plus a redirect
        expect(response).to have_http_status(:found)
        expect(flash[:alert]).to eq(Organizations::PositionChangesController::ALREADY_FINALIZED_MESSAGE)
        expect(delete_change.reload.status).to eq("approved") # unchanged
      end

      it "redirects with flash[:alert] when the change is already rejected (W7 helper)" do
        make_rejected!(delete_change, delete_admin)
        sign_in(delete_admin)
        delete delete_path
        expect(response).to have_http_status(:found)
        expect(flash[:alert]).to eq(Organizations::PositionChangesController::ALREADY_FINALIZED_MESSAGE)
        expect(delete_change.reload.rejected_by_id).to eq(delete_admin.id) # unchanged
      end

      it "404s for unknown id" do
        sign_in(delete_admin)
        delete "/organizations/#{delete_organization.id}/position_changes/99999999"
        expect(response).to have_http_status(:not_found)
      end

      # @lat: [[organization-position-removal#Position lookup stays within the organization]]
      it "404s when the change belongs to a different organization (cross-org write defense, IN-05)" do
        other_org = create(:organization)
        other_position = create(:organization_bill_position, organization: other_org)
        other_change = create(:organization_bill_position_change,
          organization_bill_position: other_position,
          updated_by: delete_admin,
          status: :pending)
        sign_in(delete_admin)
        delete "/organizations/#{delete_organization.id}/position_changes/#{other_change.id}"
        expect(response).to have_http_status(:not_found)
        expect(other_change.reload.status).to eq("pending") # untouched
        expect(other_change.rejected_by_id).to be_nil
        expect(other_change.rejected_at).to be_nil
      end
    end

    context "JSON / bearer auth (mobile)" do
      it "401s with the unauthenticated envelope when no bearer is presented" do
        # The JSON branch of authenticate_sway_user! returns the :unauthorized envelope
        delete delete_path, headers: {"Accept" => "application/json"}
        expect(response).to have_http_status(:unauthorized)
        body = JSON.parse(response.body)
        expect(body.dig("error", "code")).to eq("unauthenticated")
      end

      it "403 JSON 'Forbidden' for a non-admin org member" do
        # authenticate_as is the shared helper, not a local stand-in
        delete delete_path, headers: authenticate_as(delete_non_admin_member).merge("Accept" => "application/json")
        expect(response).to have_http_status(:forbidden)
        expect(JSON.parse(response.body).dig("error", "code")).to eq("forbidden")
      end

      it "403 JSON 'Forbidden' for a sway admin who is not an org member" do
        # Built with the :sway_admin trait, NOT is_sway_admin: true
        sway_admin = create(:user, :sway_admin)
        delete delete_path, headers: authenticate_as(sway_admin).merge("Accept" => "application/json")
        expect(response).to have_http_status(:forbidden)
        expect(JSON.parse(response.body).dig("error", "code")).to eq("forbidden")
      end

      it "returns 204 No Content (empty body) on admin success and soft-rejects the row" do
        expect {
          delete delete_path, headers: authenticate_as(delete_admin).merge("Accept" => "application/json")
        }.to change { delete_change.reload.status }.from("pending").to("rejected")
        expect(response).to have_http_status(:no_content)
        expect(response.body).to be_blank
        expect(delete_change.rejected_by_id).to eq(delete_admin.id)
        expect(delete_change.rejected_at).to be_present
      end

      it "returns 422 with literal { error: 'Change is already finalized.' } when already approved (W7 helper)" do
        make_approved!(delete_change, delete_admin)
        delete delete_path, headers: authenticate_as(delete_admin).merge("Accept" => "application/json")
        # The JSON branch renders { error: "..." }, NOT the { redirect, flash } body
        expect(response).to have_http_status(:unprocessable_content)
        body = JSON.parse(response.body)
        expect(body["error"]["code"]).to eq("already_finalized")
        expect(body["error"]["message"]).to eq(Organizations::PositionChangesController::ALREADY_FINALIZED_MESSAGE)
        expect(delete_change.reload.status).to eq("approved")
      end

      it "returns 422 with literal { error: 'Change is already finalized.' } when already rejected (W7 helper)" do
        make_rejected!(delete_change, delete_admin)
        delete delete_path, headers: authenticate_as(delete_admin).merge("Accept" => "application/json")
        expect(response).to have_http_status(:unprocessable_content)
        body = JSON.parse(response.body)
        expect(body["error"]["code"]).to eq("already_finalized")
        expect(body["error"]["message"]).to eq(Organizations::PositionChangesController::ALREADY_FINALIZED_MESSAGE)
      end

      it "404s for unknown id" do
        delete "/organizations/#{delete_organization.id}/position_changes/99999999",
          headers: authenticate_as(delete_admin).merge("Accept" => "application/json")
        expect(response).to have_http_status(:not_found)
      end

      # The JSON twin of the cross-organization defense above. One shared
      # set_change before_action guards both formats.
      it "404s when the change belongs to a different organization (cross-org write defense, IN-05)" do
        other_org = create(:organization)
        other_position = create(:organization_bill_position, organization: other_org)
        other_change = create(:organization_bill_position_change,
          organization_bill_position: other_position,
          updated_by: delete_admin,
          status: :pending)
        delete "/organizations/#{delete_organization.id}/position_changes/#{other_change.id}",
          headers: authenticate_as(delete_admin).merge("Accept" => "application/json")
        expect(response).to have_http_status(:not_found)
        expect(other_change.reload.status).to eq("pending") # untouched
        expect(other_change.rejected_by_id).to be_nil
        expect(other_change.rejected_at).to be_nil
      end
    end
  end
end
