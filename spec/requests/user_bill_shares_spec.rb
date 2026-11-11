# frozen_string_literal: true

require "rails_helper"

# @lat: [[domain-entities#People and identity]]
RSpec.describe "UserBillShares", type: :request do
  include_context "SessionDouble"
  include_context "Setup"

  let(:sway_and_user) { setup }
  let(:sway_locale) { sway_and_user.first }
  let(:user) { sway_and_user.last }
  let(:bill) { create(:bill, sway_locale:) }

  describe "POST /user_bill_shares" do
    context "when authenticated with cookies (browser / Inertia)" do
      before { sign_in(user) }

      it "creates an unredeemed UserBillShare, sets flash[:bill_share_path], and redirects to bill_path" do
        expect do
          post "/user_bill_shares", params: {bill_id: bill.id}
        end.to change(UserBillShare, :count).by(1)

        share = UserBillShare.last!
        expect(share.user).to eq(user)
        expect(share.bill).to eq(bill)
        expect(share.redeemed_at).to be_nil
        expect(flash[:bill_share_path]).to eq("/bill_shares/#{share.share_uuid}")
        expect(response).to redirect_to(bill_path(bill))
      end

      it "redirects to safe referer if present" do
        post "/user_bill_shares",
          params: {bill_id: bill.id},
          headers: {"HTTP_REFERER" => "/bills/#{bill.id}?view=details"}

        expect(response).to redirect_to("/bills/#{bill.id}?view=details")
      end

      it "falls back to bill_path if referer is unsafe or external" do
        post "/user_bill_shares",
          params: {bill_id: bill.id},
          headers: {"HTTP_REFERER" => "https://evil.example.com/phish"}

        expect(response).to redirect_to(bill_path(bill))
      end

      it "is idempotent for repeated requests by the same user for the same bill" do
        post "/user_bill_shares", params: {bill_id: bill.id}
        first_path = flash[:bill_share_path]

        expect do
          post "/user_bill_shares", params: {bill_id: bill.id}
        end.not_to change(UserBillShare, :count)

        expect(flash[:bill_share_path]).to eq(first_path)
        expect(response).to redirect_to(bill_path(bill))
      end

      it "redirects to bills_path with alert 'Bill not found.' if bill_id is missing" do
        expect do
          post "/user_bill_shares", params: {}
        end.not_to change(UserBillShare, :count)

        expect(response).to redirect_to(bills_path)
        expect(flash[:alert]).to eq("Bill not found.")
      end

      it "redirects to bills_path with alert 'Bill not found.' if bill does not exist" do
        expect do
          post "/user_bill_shares", params: {bill_id: 999_999_999}
        end.not_to change(UserBillShare, :count)

        expect(response).to redirect_to(bills_path)
        expect(flash[:alert]).to eq("Bill not found.")
      end

      it "rejects non-scalar bill_id parameters safely without raising 500" do
        expect do
          post "/user_bill_shares", params: {bill_id: [bill.id]}
        end.not_to change(UserBillShare, :count)

        expect(response).to redirect_to(bills_path)
        expect(flash[:alert]).to eq("Bill not found.")
      end
    end

    context "when authenticated with JSON / Bearer (mobile / API)" do
      let(:raw_token) { "test-bearer-token-#{SecureRandom.hex(8)}" }
      let!(:api_key) { ApiKey.create!(bearer: user, token: raw_token) }

      it "creates unredeemed record and returns 200 OK with resource JSON via Accept header" do
        sign_in(user)
        expect do
          post "/user_bill_shares",
            params: {bill_id: bill.id},
            headers: {"Accept" => "application/json"}
        end.to change(UserBillShare, :count).by(1)

        expect(response).to have_http_status(:ok)
        share = UserBillShare.last!
        expect(share.redeemed_at).to be_nil
        expect(response.parsed_body).to eq(
          "id" => share.id,
          "bill_id" => bill.id,
          "share_uuid" => share.share_uuid,
          "share_path" => "/bill_shares/#{share.share_uuid}"
        )
      end

      it "creates unredeemed record idempotently with Bearer token authentication" do
        expect do
          post "/user_bill_shares",
            params: {bill_id: bill.id},
            headers: {
              "Authorization" => "Bearer #{raw_token}",
              "Accept" => "application/json"
            }
        end.to change(UserBillShare, :count).by(1)

        expect(response).to have_http_status(:ok)
        share = UserBillShare.last!
        expect(response.parsed_body["share_uuid"]).to eq(share.share_uuid)

        expect do
          post "/user_bill_shares",
            params: {bill_id: bill.id},
            headers: {
              "Authorization" => "Bearer #{raw_token}",
              "Accept" => "application/json"
            }
        end.not_to change(UserBillShare, :count)

        expect(response).to have_http_status(:ok)
        expect(response.parsed_body["share_uuid"]).to eq(share.share_uuid)
      end

      it "returns 404 JSON when bill_id is missing or unknown" do
        post "/user_bill_shares",
          params: {bill_id: 999_999_999},
          headers: {
            "Authorization" => "Bearer #{raw_token}",
            "Accept" => "application/json"
          }

        expect(response).to have_http_status(:not_found)
        expect(response.parsed_body).to eq(
          "error" => {
            "code" => "not_found",
            "message" => "Bill not found."
          }
        )
      end
    end

    context "when unauthenticated" do
      before do
        bill
        session_hash.clear
      end

      it "redirects to root_path for HTML requests" do
        post "/user_bill_shares", params: {bill_id: bill.id}
        expect(response).to redirect_to(root_path)
      end

      it "returns 401 for JSON requests" do
        post "/user_bill_shares",
          params: {bill_id: bill.id},
          headers: {"Accept" => "application/json"}

        expect(response).to have_http_status(:unauthorized)
        expect(response.parsed_body).to eq(
          "error" => {
            "code" => "unauthenticated",
            "message" => "Sign in to continue."
          }
        )
      end
    end
  end

  describe "GET /bill_shares/:share_uuid" do
    it "redeems the share and redirects to bill_path when opened by an anonymous user" do
      share = create(:user_bill_share, user:, bill:)
      session_hash.clear
      expect(share.redeemed_at).to be_nil

      get "/bill_shares/#{share.share_uuid}"

      expect(response).to redirect_to(bill_path(bill.id))
      expect(share.reload.redeemed_at).to be_present
    end

    it "redeems the share and redirects to bill_path when opened by a different signed-in user" do
      share = create(:user_bill_share, user:, bill:)
      other_user = create(:user, is_registration_complete: true, registration_status: "completed")
      sign_in(other_user)

      get "/bill_shares/#{share.share_uuid}"

      expect(response).to redirect_to(bill_path(bill.id))
      expect(share.reload.redeemed_at).to be_present
    end

    it "redirects to bill_path without redeeming when opened by the creator" do
      share = create(:user_bill_share, user:, bill:)
      sign_in(user)

      get "/bill_shares/#{share.share_uuid}"

      expect(response).to redirect_to(bill_path(bill.id))
      expect(share.reload.redeemed_at).to be_nil
    end

    it "does not update redeemed_at on subsequent redemptions" do
      share = create(:user_bill_share, user:, bill:)
      session_hash.clear
      get "/bill_shares/#{share.share_uuid}"
      first_redeemed_at = share.reload.redeemed_at
      expect(first_redeemed_at).to be_present

      get "/bill_shares/#{share.share_uuid}"
      expect(share.reload.redeemed_at).to eq(first_redeemed_at)
      expect(response).to redirect_to(bill_path(bill.id))
    end

    it "redirects to bills_path with alert 'Bill not found.' for unknown share_uuid" do
      session_hash.clear
      get "/bill_shares/non-existent-uuid"

      expect(response).to redirect_to(bills_path)
      expect(flash[:alert]).to eq("Bill not found.")
    end

    it "redirects to bills_path with alert 'Bill not found.' without redeeming when the bill is archived" do
      share = create(:user_bill_share, user:, bill:)
      bill.update_column(:archived_at, Time.current)
      session_hash.clear

      get "/bill_shares/#{share.share_uuid}"

      expect(response).to redirect_to(bills_path)
      expect(flash[:alert]).to eq("Bill not found.")
      expect(share.reload.redeemed_at).to be_nil
    end
  end
end
