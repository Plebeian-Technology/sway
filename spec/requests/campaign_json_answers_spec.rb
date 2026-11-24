# frozen_string_literal: true

require "rails_helper"

# @lat: [[mobile-bill-creator#Sections#The campaign drafts section#Answering campaign writes in JSON]]
RSpec.describe "Campaign writes for a bearer request", type: :request do
  let(:admin) { create(:user, :sway_admin) }
  let(:bill) { create(:bill) }
  let(:json_headers) { authenticate_as(admin).merge("Accept" => "application/json") }
  let(:non_admin_headers) do
    user = create(:user)
    create(:user_legislator, user: user)
    user.complete!
    authenticate_as(user).merge("Accept" => "application/json")
  end

  let!(:provisioning) do
    create(:bill_llm_provisioning, bill: bill,
      extracted_testimony: "R" * 900,
      cleaned_testimony: {
        "version" => 1, "text" => "C" * 900,
        "counts" => {"raw_chars" => 900, "cleaned_chars" => 900},
        "letters" => [],
        "campaign_drafts" => [
          {"id" => "grp1", "letter_positions" => [], "shared_text" => "shared template line",
           "sender_count" => 3, "letter_count" => 3, "added_words" => "", "senders_added_words_left_out" => 0}
        ]
      },
      cleaned_testimony_at: 1.hour.ago)
  end

  let(:approval) { {name: "Complete Streets Letter", support: "support", summary: "Backs it", content_hash: "grp1"} }

  describe "POST /bills/:bill_id/campaigns" do
    it "approves the campaign and answers 200 JSON with the notice" do
      expect {
        post "/bills/#{bill.id}/campaigns", params: approval, headers: json_headers
      }.to change(Campaign, :count).by(1)

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body).to eq("notice" => "Approved a campaign position on #{bill.external_id}.")
    end

    it "answers a refusal with 422 and the reason under campaign_position" do
      post "/bills/#{bill.id}/campaigns", params: approval.merge(summary: "  "), headers: json_headers

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.parsed_body.dig("error", "code")).to eq("validation_failed")
      expect(response.parsed_body.dig("error", "details", "campaign_position")).to eq("A summary is required")
      expect(Campaign.count).to eq(0)
    end

    it "answers a non-admin with 403 JSON" do
      post "/bills/#{bill.id}/campaigns", params: approval,
        headers: non_admin_headers

      expect(response).to have_http_status(:forbidden)
      expect(response.parsed_body.dig("error", "code")).to eq("forbidden")
      expect(Campaign.count).to eq(0)
    end
  end

  {
    "reject_draft" => "Rejected a campaign draft on %s.",
    "restore_draft" => "Restored a campaign draft on %s.",
    "mark_individual_draft" => "Marked a campaign draft as individual letters on %s."
  }.each do |action, notice|
    describe "POST /bills/:bill_id/campaigns/#{action}" do
      it "records the decision and answers 200 JSON with the notice" do
        post "/bills/#{bill.id}/campaigns/#{action}", params: {content_hash: "grp1"}, headers: json_headers

        expect(response).to have_http_status(:ok)
        expect(response.parsed_body).to eq("notice" => format(notice, bill.external_id))
      end

      it "answers a request that names no draft with 422 and the reason under campaign_position" do
        post "/bills/#{bill.id}/campaigns/#{action}", params: {content_hash: ""}, headers: json_headers

        expect(response).to have_http_status(:unprocessable_content)
        expect(response.parsed_body.dig("error", "details", "campaign_position")).to eq(
          "A campaign draft was named with no identity to check it against"
        )
      end

      it "answers a non-admin with 403 JSON" do
        post "/bills/#{bill.id}/campaigns/#{action}", params: {content_hash: "grp1"},
          headers: non_admin_headers

        expect(response).to have_http_status(:forbidden)
        expect(response.parsed_body.dig("error", "code")).to eq("forbidden")
      end
    end
  end

  it "records a rejection the phone sent" do
    post "/bills/#{bill.id}/campaigns/reject_draft", params: {content_hash: "grp1"}, headers: json_headers

    expect(provisioning.reload.rejected_campaign_draft_hash_list).to eq(["grp1"])
  end

  context "from the web" do
    include_context "SessionDouble"

    before { session_hash[:user_id] = admin.id }

    it "keeps the approve redirect and notice" do
      post "/bills/#{bill.id}/campaigns", params: approval

      expect(response).to redirect_to(positions_bill_creator_path(bill))
      expect(flash[:notice]).to eq("Approved a campaign position on #{bill.external_id}.")
    end

    it "keeps the approve refusal redirect with its Inertia error" do
      post "/bills/#{bill.id}/campaigns", params: approval.merge(summary: "  ")

      expect(response).to redirect_to(positions_bill_creator_path(bill))
      inertia_errors = session[:inertia_errors] || {}
      expect(inertia_errors[:campaign_position] || inertia_errors["campaign_position"]).to eq("A summary is required")
    end

    it "keeps the reject redirect and notice" do
      post "/bills/#{bill.id}/campaigns/reject_draft", params: {content_hash: "grp1"}

      expect(response).to redirect_to(positions_bill_creator_path(bill))
      expect(flash[:notice]).to eq("Rejected a campaign draft on #{bill.external_id}.")
    end
  end
end
