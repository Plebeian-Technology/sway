# frozen_string_literal: true

require "rails_helper"

# @lat: [[draft-refusal-redirect-refreshes-list#Draft-decision refusals refresh the list on their own]]
RSpec.describe "a refused draft decision leaves the current list on screen", type: :request do
  include_context "SessionDouble"

  before { session_hash[:user_id] = admin.id }

  let(:admin) { create(:user, :sway_admin) }
  let(:bill) { create(:bill) }

  # The state partway through the race the refusal exists for: Org A has already
  # been rejected, so the server holds [Org B, Org C] while the operator's page
  # still shows Org A at position 0.
  let!(:provisioning) do
    create(
      :bill_llm_provisioning,
      :with_diff_content,
      bill: bill,
      generation_status: "completed",
      llm_summary: "Test summary",
      llm_full_breakdown: "## Test",
      extracted_testimony: "Testimony of Org B and Org C, submitted at the hearing.",
      draft_org_positions: [
        {"org_name" => "Org B", "stance" => "support", "summary" => "Supports."},
        {"org_name" => "Org C", "stance" => "oppose", "summary" => "Opposes."}
      ]
    )
  end

  # The draft list as the browser receives it: read off the Inertia props of the
  # page the refusal redirected to, not off the database. The database being
  # right is not the claim — the claim is that the operator can SEE it.
  def draft_org_names_on_screen
    inertia.props[:bill]
      .deep_symbolize_keys
      .dig(:bill_llm_provisioning, :draft_org_positions)
      .map { |draft| draft[:org_name] }
  end

  def inertia_error
    errors = session[:inertia_errors] || {}
    errors[:org_position] || errors["org_position"]
  end

  describe "a Reject naming a draft the index no longer points at" do
    it "sends the operator to a page carrying the list as it stands now" do
      patch "/bill_draft_org_positions/#{bill.id}-1",
        params: {rejected: true, draft_org_name: "Org B"}

      expect(response).to redirect_to(positions_bill_creator_path(id: bill.id))
      follow_redirect!

      expect(inertia).to render_component(Pages::BILL_CREATOR)
      expect(draft_org_names_on_screen).to eq(["Org B", "Org C"])
    end

    it "says the list changed without asking anyone to reload" do
      patch "/bill_draft_org_positions/#{bill.id}-1",
        params: {rejected: true, draft_org_name: "Org B"}

      expect(inertia_error).to eq(DraftOrgPositionRefusals::LIST_CHANGED)
      expect(inertia_error).not_to match(/reload|refresh/i)
    end
  end

  describe "an Approve naming a draft the index no longer points at" do
    it "sends the operator to a page carrying the list as it stands now" do
      post "/bills/#{bill.id}/approve_org_position",
        params: {
          org_name: "Org B", support: "support", summary: "Supports.",
          index: 1, draft_org_name: "Org B"
        }

      expect(response).to redirect_to(positions_bill_creator_path(id: bill.id))
      follow_redirect!

      expect(inertia).to render_component(Pages::BILL_CREATOR)
      expect(draft_org_names_on_screen).to eq(["Org B", "Org C"])
    end

    it "says the list changed without asking anyone to reload" do
      post "/bills/#{bill.id}/approve_org_position",
        params: {
          org_name: "Org B", support: "support", summary: "Supports.",
          index: 1, draft_org_name: "Org B"
        }

      expect(inertia_error).to eq(DraftOrgPositionRefusals::LIST_CHANGED)
      expect(inertia_error).not_to match(/reload|refresh/i)
    end
  end
end
