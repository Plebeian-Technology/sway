# frozen_string_literal: true

require "rails_helper"

# @lat: [[identity-and-access#Sessions, cookies and bearer tokens]]
RSpec.describe "the /api/* bearer-token gate", type: :request do
  include_context "Setup"

  let!(:sway_and_user) { setup }
  let(:user) { sway_and_user.last }
  let(:raw_token) { "test-bearer-#{SecureRandom.hex(8)}" }
  let!(:api_key) { ApiKey.create!(bearer: user, token: raw_token) }

  # @lat: [[admin-gate-shared-examples#Admin-gate shared examples#Missing API credentials stop before the admin decision]]
  it "rejects a non-admin /api/ request with no token" do
    get "/api/bills"

    expect(response).to have_http_status(:unauthorized)
  end

  it "rejects an /api/admin/ request with no token" do
    post "/api/admin/organizations", params: {organizations: []}

    expect(response).to have_http_status(:unauthorized)
  end

  it "rejects an /api/admin/ request from a valid but non-admin bearer" do
    non_admin_user = create(:user, :registered)
    non_admin_token = "test-bearer-non-admin-#{SecureRandom.hex(8)}"
    ApiKey.create!(bearer: non_admin_user, token: non_admin_token)

    post "/api/admin/organizations",
      params: {organizations: []},
      headers: {"Authorization" => "Bearer #{non_admin_token}"}

    expect(response).to have_http_status(:unauthorized)
    expect(JSON.parse(response.body)["message"]).to eq("This API key does not belong to a Sway admin.")
  end

  it "lets a valid non-admin bearer through on a plain /api/ route" do
    get "/api/bills", headers: {"Authorization" => "Bearer #{raw_token}"}

    expect(response).not_to have_http_status(:unauthorized)
  end

  it "rejects an /api/admin/ request from a non-admin bearer even when an admin cookie session is present" do
    admin_user = create(:user, :sway_admin)
    sign_in(admin_user)

    non_admin_user = create(:user, :registered)
    non_admin_token = "test-bearer-non-admin-#{SecureRandom.hex(8)}"
    ApiKey.create!(bearer: non_admin_user, token: non_admin_token)

    post "/api/admin/organizations",
      params: {organizations: []},
      headers: {"Authorization" => "Bearer #{non_admin_token}"}

    expect(response).to have_http_status(:unauthorized)
    expect(JSON.parse(response.body)["message"]).to eq("This API key does not belong to a Sway admin.")
  end

  it "rejects an /api/admin/ request from a non-admin legacy Token even when an admin cookie session is present" do
    admin_user = create(:user, :sway_admin)
    sign_in(admin_user)

    non_admin_user = create(:user, :registered)
    non_admin_token = "test-token-non-admin-#{SecureRandom.hex(8)}"
    ApiKey.create!(bearer: non_admin_user, token: non_admin_token)

    post "/api/admin/organizations",
      params: {organizations: []},
      headers: {"Authorization" => "Token token=\"#{non_admin_token}\""}

    expect(response).to have_http_status(:unauthorized)
    expect(JSON.parse(response.body)["message"]).to eq("This API key does not belong to a Sway admin.")
  end

  it "rejects an /api/admin/ request with an invalid bearer token even when an admin cookie session is present" do
    admin_user = create(:user, :sway_admin)
    sign_in(admin_user)

    post "/api/admin/organizations",
      params: {organizations: []},
      headers: {"Authorization" => "Bearer invalid-admin-token"}

    expect(response).to have_http_status(:unauthorized)
  end
end
