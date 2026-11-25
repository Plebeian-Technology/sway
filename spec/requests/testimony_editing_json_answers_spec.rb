# frozen_string_literal: true

require "rails_helper"

# @lat: [[mobile-bill-creator#Sections#The testimony section#Answering testimony writes in JSON]]
RSpec.describe "Testimony writes for a bearer request", type: :request do
  let(:admin) { create(:user, :sway_admin) }
  let(:bill) { create(:bill) }
  let(:json_headers) { authenticate_as(admin).merge("Accept" => "application/json") }
  let(:non_admin_headers) do
    user = create(:user)
    create(:user_legislator, user: user)
    user.complete!
    authenticate_as(user).merge("Accept" => "application/json")
  end

  let(:cleaned_testimony) do
    {
      "text" => "I strongly support this bill for our community.",
      "counts" => {},
      "letters" => [
        {"position" => 1, "source_kind" => "person_speaking_for_self", "stance" => "support",
         "characters" => 47, "character_offset" => 0}
      ]
    }
  end

  let!(:provisioning) do
    create(:bill_llm_provisioning, bill: bill,
      supplemental_testimony: "Stored testimony.",
      cleaned_testimony: cleaned_testimony)
  end

  describe "PATCH /bills/:id/supplemental_testimony" do
    it "saves the testimony and answers 200 JSON" do
      patch "/bills/#{bill.id}/supplemental_testimony",
        params: {supplemental_testimony: "New testimony."}, headers: json_headers

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body).to eq({})
      expect(provisioning.reload.supplemental_testimony).to eq("New testimony.")
    end

    it "clears the testimony and answers 200 JSON" do
      patch "/bills/#{bill.id}/supplemental_testimony",
        params: {clear_supplemental_testimony: true}, headers: json_headers

      expect(response).to have_http_status(:ok)
      expect(provisioning.reload.supplemental_testimony).to be_nil
    end

    it "answers a non-admin with 403 JSON" do
      patch "/bills/#{bill.id}/supplemental_testimony",
        params: {clear_supplemental_testimony: true}, headers: non_admin_headers

      expect(response).to have_http_status(:forbidden)
      expect(response.parsed_body.dig("error", "code")).to eq("forbidden")
      expect(provisioning.reload.supplemental_testimony).to eq("Stored testimony.")
    end
  end

  describe "PATCH /bills/:id/testimony_letter_stance" do
    it "changes the stance and answers 200 JSON" do
      patch "/bills/#{bill.id}/testimony_letter_stance",
        params: {position: 1, stance: "oppose"}, headers: json_headers

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body).to eq({})
      letter = provisioning.reload.cleaned_testimony["letters"].first
      expect(letter).to include("stance" => "oppose", "stance_override" => true)
    end

    it "removes the letter and answers 200 JSON" do
      patch "/bills/#{bill.id}/testimony_letter_stance",
        params: {position: 1, excluded: true}, headers: json_headers

      expect(response).to have_http_status(:ok)
      expect(provisioning.reload.cleaned_testimony["letters"].first["excluded"]).to eq(true)
    end

    it "answers a letter that is not on the bill with 422 and the reason under testimony_letter_stance" do
      patch "/bills/#{bill.id}/testimony_letter_stance",
        params: {position: 9, stance: "oppose"}, headers: json_headers

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.parsed_body.dig("error", "code")).to eq("validation_failed")
      expect(response.parsed_body.dig("error", "details", "testimony_letter_stance")).to eq("Testimony letter not found.")
    end

    it "answers a bill with no cleaned letters with 422 and the reason under testimony_letter_stance" do
      provisioning.update!(cleaned_testimony: nil)

      patch "/bills/#{bill.id}/testimony_letter_stance",
        params: {position: 1, stance: "oppose"}, headers: json_headers

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.parsed_body.dig("error", "details", "testimony_letter_stance")).to eq(
        "No cleaned testimony letters available on this bill."
      )
    end

    it "keeps answering an invalid stance with 422 and its error" do
      patch "/bills/#{bill.id}/testimony_letter_stance",
        params: {position: 1, stance: "maybe"}, headers: json_headers

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.parsed_body["error"]).to eq("Invalid position or stance (expected support, oppose, or neutral).")
    end

    it "answers a non-admin with 403 JSON" do
      patch "/bills/#{bill.id}/testimony_letter_stance",
        params: {position: 1, stance: "oppose"}, headers: non_admin_headers

      expect(response).to have_http_status(:forbidden)
      expect(response.parsed_body.dig("error", "code")).to eq("forbidden")
      expect(provisioning.reload.cleaned_testimony["letters"].first["stance"]).to eq("support")
    end
  end

  context "from the web" do
    include_context "SessionDouble"

    before { session_hash[:user_id] = admin.id }

    it "keeps the supplemental testimony redirect" do
      patch "/bills/#{bill.id}/supplemental_testimony", params: {supplemental_testimony: "New testimony."}

      expect(response).to redirect_to(positions_bill_creator_path(bill))
    end

    it "keeps the stance redirect and notice" do
      patch "/bills/#{bill.id}/testimony_letter_stance", params: {position: 1, stance: "oppose"}

      expect(response).to redirect_to(positions_bill_creator_path(bill))
      expect(flash[:notice]).to eq("Updated testimony letter stance to oppose on #{bill.external_id}.")
    end

    it "keeps the missing letter redirect with its Inertia error" do
      patch "/bills/#{bill.id}/testimony_letter_stance",
        params: {position: 9, stance: "oppose"},
        headers: {"HTTP_REFERER" => "http://www.example.com/bills/#{bill.id}"}

      expect(response).to redirect_to("/bills/#{bill.id}")
      inertia_errors = session[:inertia_errors] || {}
      expect(inertia_errors[:testimony_letter_stance] || inertia_errors["testimony_letter_stance"]).to eq(
        "Testimony letter not found."
      )
    end

    it "keeps the no letters redirect with its Inertia error" do
      provisioning.update!(cleaned_testimony: nil)

      patch "/bills/#{bill.id}/testimony_letter_stance", params: {position: 1, stance: "oppose"}

      expect(response).to redirect_to(positions_bill_creator_path(bill))
      inertia_errors = session[:inertia_errors] || {}
      expect(inertia_errors[:testimony_letter_stance] || inertia_errors["testimony_letter_stance"]).to eq(
        "No cleaned testimony letters available on this bill."
      )
    end
  end
end
