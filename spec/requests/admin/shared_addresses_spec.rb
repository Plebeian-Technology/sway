# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Admin::SharedAddresses", type: :request do
  include_context "SessionDouble"

  include_examples "requires sway admin",
    verb: :get,
    path: "/admin/shared_addresses"

  context "with a bearer token and Accept: application/json" do
    let(:api_token) { SecureRandom.hex(32) }
    let(:headers) { {"Authorization" => "Bearer #{api_token}", "Accept" => "application/json"} }

    # @lat: [[mobile-admin-area#The shared addresses screen]]
    it "serves the shared addresses as JSON to a sway admin" do
      ApiKey.create!(bearer: create(:user, :sway_admin), token: api_token)
      address = create(:address)
      create(:user_address, user: create(:user), address:)
      create(:user_address, user: create(:user), address:)

      get "/admin/shared_addresses", headers: headers

      expect(response).to have_http_status(:ok)
      expect(response.media_type).to eq("application/json")
      expect(response.parsed_body).to eq("shared_addresses" => [{"address_ids" => [address.id], "user_count" => 2}])
    end

    it "refuses a non-admin with a forbidden JSON error" do
      user = create(:user)
      create(:user_legislator, user: user)
      user.complete!
      ApiKey.create!(bearer: user, token: api_token)

      get "/admin/shared_addresses", headers: headers

      expect(response).to have_http_status(:forbidden)
      expect(response.parsed_body.dig("error", "code")).to eq("forbidden")
    end
  end

  context "as a sway admin" do
    let(:admin) { create(:user, :sway_admin) }

    before { session_hash[:user_id] = admin.id }

    it "renders the shared addresses page with a count and traceable id per shared address" do
      address = create(:address)
      create(:user_address, user: create(:user), address:)
      create(:user_address, user: create(:user), address:)

      get "/admin/shared_addresses"

      expect(inertia).to render_component("admin/SharedAddresses")
      expect(inertia.props[:shared_addresses]).to eq([{"address_ids" => [address.id], "user_count" => 2}])
    end

    it "carries no street, city, or coordinate field in the props" do
      address = create(:address)
      create(:user_address, user: create(:user), address:)
      create(:user_address, user: create(:user), address:)

      get "/admin/shared_addresses"

      body_keys = inertia.props[:shared_addresses].flat_map(&:keys)
      expect(body_keys.uniq.sort).to eq(["address_ids", "user_count"])
      expect(response.body).not_to include(address.street)
    end

    it "omits an address given by only one registered user" do
      address = create(:address)
      create(:user_address, user: create(:user), address:)

      get "/admin/shared_addresses"

      expect(inertia.props[:shared_addresses]).to eq([])
    end
  end
end
