# frozen_string_literal: true

# @lat: [[organization-position-removal#Taking an organization's position off a bill#Position lookup stays within the organization]]

require "rails_helper"

RSpec.describe "Organizations::PositionChangesController approval-spoofing security", type: :request do
  include_context "SessionDouble"
  include_context "Setup"

  context "cross-org approval spoofing (#update — net-new vs request spec's reject-side pins)" do
    it "404s a cookie/web PATCH approve of another org's change and leaves the victim position untouched" do
      attacker_org = create(:organization)
      attacker_admin = create(:user).tap { |u| complete_registration_with_active_link(u) }
      create(:user_organization_membership, :admin, user: attacker_admin, organization: attacker_org)

      victim_org = create(:organization)
      victim_position = create(:organization_bill_position,
        organization: victim_org, support: "support", summary: "Victim org's live summary")
      victim_change = create(:organization_bill_position_change,
        organization_bill_position: victim_position,
        updated_by: attacker_admin,
        previous_support: "oppose",
        new_support: "support",
        new_summary: "Attacker-controlled summary",
        status: :pending)

      sign_in(attacker_admin)
      patch "/organizations/#{attacker_org.id}/position_changes/#{victim_change.id}"

      expect(response).to have_http_status(:not_found)
      expect(victim_change.reload.status).to eq("pending")
      expect(victim_change.approved_by_id).to be_nil
      expect(victim_position.reload.support).to eq("FOR")
      expect(victim_position.summary).to eq("Victim org's live summary")
    end

    it "404s a JSON/bearer PATCH approve of another org's change and leaves the victim position untouched" do
      attacker_org = create(:organization)
      attacker_admin = create(:user).tap { |u| complete_registration_with_active_link(u) }
      create(:user_organization_membership, :admin, user: attacker_admin, organization: attacker_org)

      victim_org = create(:organization)
      victim_position = create(:organization_bill_position,
        organization: victim_org, support: "support", summary: "Victim org's live summary")
      victim_change = create(:organization_bill_position_change,
        organization_bill_position: victim_position,
        updated_by: attacker_admin,
        previous_support: "oppose",
        new_support: "support",
        new_summary: "Attacker-controlled summary",
        status: :pending)

      patch "/organizations/#{attacker_org.id}/position_changes/#{victim_change.id}",
        headers: authenticate_as(attacker_admin).merge("Accept" => "application/json")

      expect(response).to have_http_status(:not_found)
      expect(victim_change.reload.status).to eq("pending")
      expect(victim_change.approved_by_id).to be_nil
      expect(victim_position.reload.support).to eq("FOR")
      expect(victim_position.summary).to eq("Victim org's live summary")
    end
  end
end
