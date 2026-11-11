# frozen_string_literal: true

require "rails_helper"

RSpec.describe "ProvisionalVotes", type: :request do
  # @lat: [[low-friction-voting#Provisional vote capture and cookie lifecycle]]
  include_context "Setup"

  let(:sway_and_user) { setup }
  let(:sway_locale) { sway_and_user.first }
  let(:bill) { create(:bill, sway_locale: sway_locale) }

  def decrypted_pending_vote
    jar = ActionDispatch::Cookies::CookieJar.build(request, cookies.to_hash)
    jar.encrypted[:sway_pending_vote]
  end

  describe "POST /provisional_votes" do
    it "sets an encrypted cookie and returns 200 with valid bill and FOR support" do
      post provisional_votes_path, params: {bill_id: bill.id, support: "FOR"}

      expect(response).to have_http_status(:ok)
      json = response.parsed_body
      expect(json["ok"]).to be(true)
      expect(json["pending_vote"]).to eq({"bill_id" => bill.id, "support" => "FOR"})

      expect(response.cookies["sway_pending_vote"]).to be_present
      cookie_data = decrypted_pending_vote
      expect(cookie_data["bill_id"] || cookie_data[:bill_id]).to eq(bill.id)
      expect(cookie_data["support"] || cookie_data[:support]).to eq("FOR")
    end

    it "sets an encrypted cookie and returns 200 with valid bill and AGAINST support" do
      post provisional_votes_path, params: {bill_id: bill.id, support: "against"}

      expect(response).to have_http_status(:ok)
      json = response.parsed_body
      expect(json["ok"]).to be(true)
      expect(json["pending_vote"]).to eq({"bill_id" => bill.id, "support" => "AGAINST"})

      expect(response.cookies["sway_pending_vote"]).to be_present
      cookie_data = decrypted_pending_vote
      expect(cookie_data["bill_id"] || cookie_data[:bill_id]).to eq(bill.id)
      expect(cookie_data["support"] || cookie_data[:support]).to eq("AGAINST")
    end

    it "rejects invalid support (e.g. ABSTAIN) with 422" do
      post provisional_votes_path, params: {bill_id: bill.id, support: "ABSTAIN"}

      expect(response).to have_http_status(:unprocessable_content)
      json = response.parsed_body
      expect(json["ok"]).to be(false)
      expect(json["error"]).to include("Invalid support value")
      expect(response.cookies["sway_pending_vote"]).to be_blank
    end

    it "rejects invalid support (e.g. MAYBE) with 422" do
      post provisional_votes_path, params: {bill_id: bill.id, support: "MAYBE"}

      expect(response).to have_http_status(:unprocessable_content)
      json = response.parsed_body
      expect(json["ok"]).to be(false)
      expect(response.cookies["sway_pending_vote"]).to be_blank
    end

    it "rejects nonexistent bill with 404" do
      post provisional_votes_path, params: {bill_id: 999_999, support: "FOR"}

      expect(response).to have_http_status(:not_found)
      json = response.parsed_body
      expect(json["ok"]).to be(false)
      expect(json["error"]).to include("Bill not found")
      expect(response.cookies["sway_pending_vote"]).to be_blank
    end

    it "rejects inactive bill with 422" do
      allow_any_instance_of(Bill).to receive(:active).and_return(false)

      post provisional_votes_path, params: {bill_id: bill.id, support: "FOR"}

      expect(response).to have_http_status(:unprocessable_content)
      json = response.parsed_body
      expect(json["ok"]).to be(false)
      expect(json["error"]).to include("Bill is not active")
      expect(response.cookies["sway_pending_vote"]).to be_blank
    end
  end

  describe "DELETE /provisional_votes/:id" do
    it "clears the encrypted cookie and returns 200" do
      post provisional_votes_path, params: {bill_id: bill.id, support: "FOR"}
      expect(response.cookies["sway_pending_vote"]).to be_present

      delete provisional_vote_path("current")

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body).to eq({"ok" => true})
      expect(response.cookies["sway_pending_vote"]).to be_nil
    end
  end
end
