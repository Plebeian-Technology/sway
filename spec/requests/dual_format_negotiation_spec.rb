# frozen_string_literal: true

require "rails_helper"

# @lat: [[surfaces#Delivery surfaces#Dual-rendered JSON]]
RSpec.describe "Dual-format negotiation", type: :request do
  include_context "Setup"

  let!(:sway_and_user) { setup }
  let(:sway_locale) { sway_and_user.first }
  let(:user) { sway_and_user.last }
  let(:bill) { create(:bill, sway_locale: sway_locale) }
  let(:raw_token) { "test-bearer-#{SecureRandom.hex(8)}" }
  let!(:api_key) do
    ApiKey.create!(bearer: user, token: raw_token)
  end

  describe "GET /bills/:id" do
    it "renders Inertia for cookie request" do
      sign_in(user)
      get "/bills/#{bill.id}"
      expect(response).to have_http_status(:ok).or have_http_status(:redirect)
      expect(response.content_type).not_to include("application/json")
    end

    it "renders JSON for bearer request" do
      get "/bills/#{bill.id}",
        headers: {"Authorization" => "Bearer #{raw_token}"}
      expect(response).to have_http_status(:ok).or have_http_status(:redirect)
      if response.successful?
        expect(response.content_type).to include("application/json")
      end
    end
  end

  describe "POST /user_votes" do
    it "redirects (302) to bill_path with flash for cookie request" do
      sign_in(user)
      post "/user_votes",
        params: {bill_id: bill.id, support: "FOR"}
      expect(response).to have_http_status(:redirect)
    end

    it "returns JSON { redirect, flash } envelope for bearer request" do
      post "/user_votes",
        params: {bill_id: bill.id, support: "FOR"},
        headers: {"Authorization" => "Bearer #{raw_token}"}
      expect(response).to have_http_status(:ok).or have_http_status(:found)
      expect(response.content_type).to include("application/json")
      body = JSON.parse(response.body)
      expect(body).to include("redirect")
      expect(body["flash"]).to eq("Vote saved!")
    end
  end

  # The mobile JSON response carries all_categories plus each bill's categories.
  describe "GET /bills (index)" do
    it "renders JSON with all_categories and per-bill categories for bearer request" do
      active_cat = create(:category, name: "Environment", active: true)
      create(:category, name: "OldTopic", active: false)
      categorized_bill = create(:bill, sway_locale: sway_locale)
      create(:bill_category, bill: categorized_bill, category: active_cat)

      get "/bills",
        params: {sway_locale_id: sway_locale.id},
        headers: {"Authorization" => "Bearer #{raw_token}"}

      expect(response).to have_http_status(:ok)
      expect(response.content_type).to include("application/json")

      body = JSON.parse(response.body)

      # all_categories arrives up front and lists active topics only
      expect(body["all_categories"]).to be_an(Array)
      expect(body["all_categories"]).to include("Environment")
      expect(body["all_categories"]).not_to include("OldTopic")

      # For mobile JSON the deferred bills list is built out in full, categories included
      bills_array = body["bills"]
      expect(bills_array).to be_an(Array)
      cat_bill_payload = bills_array.find { |b| b["id"] == categorized_bill.id }
      expect(cat_bill_payload).to be_present
      expect(cat_bill_payload["categories"]).to eq(["Environment"])
    end
  end

  describe "admin-gated bills#update with bearer token" do
    # @lat: [[admin-gate-shared-examples#Admin-gate shared examples#The Sway admin gate has two refusal shapes]]
    let(:non_admin_district) { create(:district, sway_locale: sway_locale, name: "District-NonAdmin-#{SecureRandom.hex(4)}") }
    let(:non_admin_legislator) { create(:legislator, district: non_admin_district) }
    let(:non_admin_user) { create(:user, :registered) }
    let!(:non_admin_user_legislator) { create(:user_legislator, user: non_admin_user, legislator: non_admin_legislator) }
    let(:non_admin_raw_token) { "test-bearer-non-admin-#{SecureRandom.hex(8)}" }
    let!(:non_admin_api_key) { ApiKey.create!(bearer: non_admin_user, token: non_admin_raw_token) }

    it "returns 403 JSON when bearer is non-admin" do
      patch "/bills/#{bill.id}",
        params: {bill: {title: "should not update"}},
        headers: {"Authorization" => "Bearer #{non_admin_raw_token}"}

      expect(response.status).to eq(403)
      expect(response.media_type).to eq("application/json")
      body = JSON.parse(response.body)
      # Errors come back wrapped as { error: { code, message } }.
      expect(body.dig("error", "code")).to eq("forbidden")
      expect(body.dig("error", "message")).to eq("Admin access required.")
    end

    it "still redirects (302) when an HTML/cookie client is non-admin" do
      sign_in(non_admin_user)
      patch "/bills/#{bill.id}",
        params: {bill: {title: "should not update"}}

      expect(response).to have_http_status(:redirect)
      expect(response.location).to include(root_path)
    end
  end

  describe "authoritative API tokens on shared routes with forgery protection enabled" do
    around do |ex|
      orig = ActionController::Base.allow_forgery_protection
      ActionController::Base.allow_forgery_protection = true
      ex.run
    ensure
      ActionController::Base.allow_forgery_protection = orig
    end

    let(:admin_user) { create(:user, :sway_admin).tap { |u| complete_registration_with_active_link(u) } }
    let(:user_b) { create(:user).tap { |u| complete_registration_with_active_link(u) } }

    before { sign_in(admin_user) }

    it "fails closed on blank, invalid, expired, or revoked Bearer tokens even when an ambient admin cookie and CSRF token are present" do
      ["Bearer", "Bearer   ", "bearer invalid-token", "Basic dXNlcjpwYXNz"].each do |header_val|
        post "/user_votes",
          params: {bill_id: bill.id, support: "FOR"},
          headers: {"Authorization" => header_val}

        expect(response.status).to eq(422).or eq(403).or eq(302)
        expect(UserVote.count).to eq(0)
      end

      expired_token = "exp-#{SecureRandom.hex(8)}"
      ApiKey.create!(bearer: admin_user, token: expired_token, expires_at: 1.hour.ago)
      device = create(:user_device, user: admin_user)
      revoked_token = "rev-#{SecureRandom.hex(8)}"
      ApiKey.create!(bearer: admin_user, user_device: device, token: revoked_token)
      device.revoke!

      get "/bills/#{bill.id}"
      csrf = response.cookies["XSRF-TOKEN"]

      [expired_token, revoked_token].each do |bad_token|
        post "/user_votes",
          params: {bill_id: bill.id, support: "FOR"},
          headers: {"Authorization" => "Bearer #{bad_token}", "X-CSRF-Token" => csrf}

        expect(response.status).to eq(401).or eq(302)
        expect(UserVote.count).to eq(0)
      end

      get "/notifications", headers: {"Authorization" => "Bearer invalid-shared-get-token"}
      expect(response).to redirect_to(root_path).or have_http_status(:unauthorized)
    end

    it "acts strictly as the bearer token user on shared routes and blocks borrowing admin privileges from ambient cookie" do
      raw_token_b = "token-b-#{SecureRandom.hex(8)}"
      ApiKey.create!(bearer: user_b, token: raw_token_b)

      post "/api/admin/organizations",
        params: {organizations: []},
        headers: {"Authorization" => "Bearer #{raw_token_b}"}
      expect(response).to have_http_status(:unauthorized)

      post "/user_votes",
        params: {bill_id: bill.id, support: "FOR"},
        headers: {"Authorization" => "Bearer #{raw_token_b}"}
      expect(UserVote.where(user: user_b, bill_id: bill.id)).to exist
      expect(UserVote.where(user: admin_user, bill_id: bill.id)).not_to exist
    end
  end
end
