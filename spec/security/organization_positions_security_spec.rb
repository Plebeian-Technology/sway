# frozen_string_literal: true

# @lat: [[organization-position-removal#Taking an organization's position off a bill#Position lookup stays within the organization]]

require "rails_helper"

RSpec.describe "Organizations::PositionsController membership + IDOR security", type: :request do
  include_context "SessionDouble"
  include_context "Setup"

  context "non-member (no membership row for the URL org)" do
    it "403s a POST create and writes no position or change rows" do
      org = create(:organization)
      bill = create(:bill, sway_locale: org.sway_locale)
      outsider = create(:user).tap { |u| complete_registration_with_active_link(u) }

      sign_in(outsider)

      expect do
        post "/organizations/#{org.id}/positions",
          params: {bill_id: bill.id, support: "support", summary: "Outsider proposal"}
      end.to change(OrganizationBillPosition, :count).by(0)
        .and change(OrganizationBillPositionChange, :count).by(0)

      expect(response).to have_http_status(:forbidden)
    end

    it "403s a PUT update and writes no change row" do
      org = create(:organization)
      position = create(:organization_bill_position,
        organization: org, support: "oppose", summary: "Org's live summary")
      outsider = create(:user).tap { |u| complete_registration_with_active_link(u) }

      sign_in(outsider)

      expect do
        put "/organizations/#{org.id}/positions/#{position.id}",
          params: {support: "support", summary: "Outsider revision"}
      end.to change(OrganizationBillPositionChange, :count).by(0)

      expect(response).to have_http_status(:forbidden)
      expect(position.reload.support).to eq("AGAINST")
      expect(position.summary).to eq("Org's live summary")
    end

    it "403s a GET new" do
      org = create(:organization)
      outsider = create(:user).tap { |u| complete_registration_with_active_link(u) }

      sign_in(outsider)

      get "/organizations/#{org.id}/positions/new"

      expect(response).to have_http_status(:forbidden)
    end
  end

  context "active member of another org (cross-org IDOR via unscoped set_position)" do
    it "404s a PUT update against a position belonging to a different org and writes no change row" do
      attacker_org = create(:organization)
      attacker = create(:user).tap { |u| complete_registration_with_active_link(u) }
      create(:user_organization_membership, :active, user: attacker, organization: attacker_org)

      victim_org = create(:organization)
      victim_position = create(:organization_bill_position,
        organization: victim_org, support: "oppose", summary: "Victim org's live summary")

      sign_in(attacker)

      expect do
        put "/organizations/#{attacker_org.id}/positions/#{victim_position.id}",
          params: {support: "support", summary: "Attacker-controlled proposal"}
      end.to change(OrganizationBillPositionChange, :count).by(0)

      expect(response).to have_http_status(:not_found)
      expect(victim_position.reload.support).to eq("AGAINST")
      expect(victim_position.summary).to eq("Victim org's live summary")
    end
  end
end
