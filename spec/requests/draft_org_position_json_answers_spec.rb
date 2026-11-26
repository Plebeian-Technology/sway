# frozen_string_literal: true

require "rails_helper"

# @lat: [[mobile-bill-creator#Sections#The draft positions section#Answering approve and review in JSON]]
RSpec.describe "Draft organization position writes for a bearer request", type: :request do
  let(:admin) { create(:user, :sway_admin) }
  let(:bill) { create(:bill) }
  let(:json_headers) { authenticate_as(admin).merge("Accept" => "application/json") }

  let!(:provisioning) do
    create(
      :bill_llm_provisioning,
      :with_diff_content,
      bill: bill,
      generation_status: "completed",
      llm_summary: "Test summary",
      llm_full_breakdown: "## Test",
      extracted_testimony: "Testimony of Org B and Org C, submitted at the hearing.",
      cleaned_testimony: {
        "version" => 1,
        "text" => "Testimony of Org B and Org C, submitted at the hearing.",
        "counts" => {"raw_chars" => 56, "cleaned_chars" => 56},
        "letters" => [
          {"position" => 0, "character_offset" => 0, "characters" => 56,
           "sender_address" => nil, "sender_domain" => nil,
           "source_kind" => "named_organization", "source_evidence" => nil}
        ],
        "campaign_drafts" => []
      },
      cleaned_testimony_at: Time.zone.now,
      draft_org_positions: [
        {"org_name" => "Org B", "stance" => "support", "summary" => "Supports."},
        {"org_name" => "Org C", "stance" => "oppose", "summary" => "Opposes."}
      ]
    )
  end

  def draft_org_names
    provisioning.reload.draft_org_positions.map { |d| d["org_name"] }
  end

  describe "POST /bills/:id/approve_org_position" do
    it "approves the draft and answers 200 JSON" do
      expect {
        post "/bills/#{bill.id}/approve_org_position",
          params: {org_name: "Org B", support: "support", summary: "Supports.", index: 0, draft_org_name: "Org B"},
          headers: json_headers
      }.to change(OrganizationBillPosition, :count).by(1)

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body).to eq({})
    end

    it "answers a refusal with 422 and the reason under org_position" do
      post "/bills/#{bill.id}/approve_org_position",
        params: {org_name: "Org B", support: "support", summary: "Supports.", index: 1, draft_org_name: "Org B"},
        headers: json_headers

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.parsed_body.dig("error", "code")).to eq("validation_failed")
      expect(response.parsed_body.dig("error", "details", "org_position")).to eq(DraftOrgPositionRefusals::LIST_CHANGED)
      expect(OrganizationBillPosition.count).to eq(0)
    end

    it "flags a private-individual refusal so the phone can offer the override" do
      text = "From: resident@gmail.com\nI support this bill.\n\nAlex Example\n100 Example Street\nBaltimore, MD 21201\n"
      provisioning.update!(
        cleaned_testimony: {
          "version" => 1, "text" => text, "counts" => {},
          "letters" => [
            {"position" => 0, "character_offset" => 0, "characters" => text.length,
             "sender_address" => "resident@gmail.com", "sender_domain" => "gmail.com",
             "source_kind" => "person_speaking_for_self", "source_evidence" => nil}
          ]
        },
        draft_org_positions: [{"org_name" => "Alex Example", "stance" => "support", "summary" => "Supports the bill."}]
      )

      post "/bills/#{bill.id}/approve_org_position",
        params: {org_name: "Alex Example", support: "support", summary: "Supports the bill.", index: 0,
                 draft_org_name: "Alex Example"},
        headers: json_headers

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.parsed_body.dig("error", "details", "org_position")).to match(/person writing for/i)
      expect(response.parsed_body.dig("error", "details", "private_individual_refusal")).to be(true)
    end
  end

  describe "PATCH /bill_draft_org_positions/:bill_id-:index" do
    it "rejects the draft and answers 200 JSON" do
      patch "/bill_draft_org_positions/#{bill.id}-0",
        params: {rejected: true, draft_org_name: "Org B"},
        headers: json_headers

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body).to eq({})
      expect(draft_org_names).to eq(["Org C"])
    end

    it "edits the draft and answers 200 JSON" do
      patch "/bill_draft_org_positions/#{bill.id}-1",
        params: {draft_org_name: "Org C", stance: "support", summary: "Amended."},
        headers: json_headers

      expect(response).to have_http_status(:ok)
      expect(provisioning.reload.draft_org_positions.last).to include("stance" => "support", "summary" => "Amended.")
    end

    it "answers a reject of a draft already gone with 200 JSON" do
      patch "/bill_draft_org_positions/#{bill.id}-5",
        params: {rejected: true, draft_org_name: "Org Z"},
        headers: json_headers

      expect(response).to have_http_status(:ok)
      expect(draft_org_names).to eq(["Org B", "Org C"])
    end

    it "answers a changed list with 422 and the reason under org_position" do
      patch "/bill_draft_org_positions/#{bill.id}-1",
        params: {rejected: true, draft_org_name: "Org B"},
        headers: json_headers

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.parsed_body.dig("error", "code")).to eq("validation_failed")
      expect(response.parsed_body.dig("error", "details", "org_position")).to eq(DraftOrgPositionRefusals::LIST_CHANGED)
      expect(draft_org_names).to eq(["Org B", "Org C"])
    end

    it "answers an invalid edit with 422 and the server's message" do
      patch "/bill_draft_org_positions/#{bill.id}-0",
        params: {draft_org_name: "Org B", stance: "maybe"},
        headers: json_headers

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.parsed_body["error"]).to eq("invalid_stance")
      expect(response.parsed_body["message"]).to start_with("support must be one of")
    end
  end

  context "from the web" do
    include_context "SessionDouble"

    before { session_hash[:user_id] = admin.id }

    it "keeps the approve redirect and notice" do
      post "/bills/#{bill.id}/approve_org_position",
        params: {org_name: "Org B", support: "support", summary: "Supports.", index: 0, draft_org_name: "Org B"}

      expect(response).to redirect_to(positions_bill_creator_path(bill))
      expect(flash[:notice]).to eq("Approved Org B on #{bill.external_id}.")
    end

    it "keeps the reject redirect and notice" do
      patch "/bill_draft_org_positions/#{bill.id}-0", params: {rejected: true, draft_org_name: "Org B"}

      expect(response).to redirect_to(positions_bill_creator_path(id: bill.id))
      expect(flash[:notice]).to eq("Rejected Org B on #{bill.external_id}.")
    end

    it "keeps the changed-list redirect with its Inertia error" do
      patch "/bill_draft_org_positions/#{bill.id}-1", params: {rejected: true, draft_org_name: "Org B"}

      expect(response).to redirect_to(positions_bill_creator_path(id: bill.id))
      inertia_errors = session[:inertia_errors] || {}
      expect(inertia_errors[:org_position] || inertia_errors["org_position"]).to eq(DraftOrgPositionRefusals::LIST_CHANGED)
    end
  end
end
