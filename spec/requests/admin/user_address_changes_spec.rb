# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Admin::UserAddressChanges", type: :request do
  include_context "SessionDouble"

  include_examples "requires sway admin",
    verb: :get,
    path: "/admin/user_address_changes"

  context "with a bearer token and Accept: application/json" do
    let(:api_token) { SecureRandom.hex(32) }
    let(:headers) { {"Authorization" => "Bearer #{api_token}", "Accept" => "application/json"} }

    # @lat: [[mobile-admin-area#The user address changes screen]]
    it "serves the user address changes as JSON to a sway admin" do
      ApiKey.create!(bearer: create(:user, :sway_admin), token: api_token)
      baltimore = create(:sway_locale, city: "baltimore", region_name: "maryland", country: "united_states")
      annapolis = create(:sway_locale, city: "annapolis", region_name: "maryland", country: "united_states")
      change = create(
        :user_address_change,
        previous_sway_locale_ids: [baltimore.id],
        new_sway_locale_ids: [annapolis.id],
        deactivated_district_ids: [10],
        activated_district_ids: [20],
        prior_vote_count: 2,
        prior_voted_bill_ids: [501, 502]
      )

      get "/admin/user_address_changes", headers: headers

      expect(response).to have_http_status(:ok)
      expect(response.media_type).to eq("application/json")
      row = response.parsed_body.fetch("user_address_changes").sole
      expect(row).to include(
        "id" => change.id,
        "previous_sway_locale_names" => [baltimore.name],
        "new_sway_locale_names" => [annapolis.name],
        "prior_vote_count" => 2,
        "cross_district" => true,
        "cross_sway_locale" => true,
        "voted_before_switch" => true,
        "user_switch_count" => 1
      )
    end

    it "refuses a non-admin with a forbidden JSON error" do
      user = create(:user)
      create(:user_legislator, user: user)
      user.complete!
      ApiKey.create!(bearer: user, token: api_token)

      get "/admin/user_address_changes", headers: headers

      expect(response).to have_http_status(:forbidden)
      expect(response.parsed_body.dig("error", "code")).to eq("forbidden")
    end
  end

  context "as a sway admin" do
    let(:admin) { create(:user, :sway_admin) }

    before { session_hash[:user_id] = admin.id }

    it "renders the user address changes page ordered most-recent-first with audit fields and switch counts" do
      baltimore = create(:sway_locale, city: "baltimore", region_name: "maryland", country: "united_states")
      annapolis = create(:sway_locale, city: "annapolis", region_name: "maryland", country: "united_states")
      user = create(:user)
      address_a = create(:address, street: "100 Secret Ave", latitude: "39.2904", longitude: "-76.6122")
      address_b = create(:address, street: "200 Hidden Blvd", latitude: "38.9784", longitude: "-76.4922")
      address_c = create(:address, street: "300 Private Ln", latitude: "39.1000", longitude: "-76.5000")

      older_change = create(
        :user_address_change,
        user:,
        previous_address: address_a,
        new_address: address_b,
        deactivated_legislator_ids: [1, 2],
        activated_legislator_ids: [1, 2],
        deactivated_district_ids: [10],
        activated_district_ids: [10],
        previous_sway_locale_ids: [baltimore.id],
        new_sway_locale_ids: [baltimore.id],
        prior_vote_count: 0,
        prior_voted_bill_ids: [],
        prior_voted_sway_locale_ids: [],
        created_at: 2.days.ago
      )
      newer_change = create(
        :user_address_change,
        user:,
        previous_address: address_b,
        new_address: address_c,
        deactivated_legislator_ids: [1, 2],
        activated_legislator_ids: [3, 4],
        deactivated_district_ids: [10],
        activated_district_ids: [20],
        previous_sway_locale_ids: [baltimore.id],
        new_sway_locale_ids: [annapolis.id],
        prior_vote_count: 2,
        prior_voted_bill_ids: [501, 502],
        prior_voted_sway_locale_ids: [baltimore.id],
        created_at: 1.hour.ago
      )

      get "/admin/user_address_changes"

      expect(response).to have_http_status(:ok)
      expect(inertia).to render_component("admin/UserAddressChanges")

      rows = inertia.props[:user_address_changes]
      expect(rows.map { |row| row["id"] || row[:id] }).to eq([newer_change.id, older_change.id])

      first_row = rows.first.transform_keys(&:to_s)
      expect(first_row).to include(
        "id" => newer_change.id,
        "user_id" => user.id,
        "previous_address_id" => address_b.id,
        "new_address_id" => address_c.id,
        "deactivated_legislator_ids" => [1, 2],
        "activated_legislator_ids" => [3, 4],
        "deactivated_district_ids" => [10],
        "activated_district_ids" => [20],
        "previous_sway_locale_ids" => [baltimore.id],
        "new_sway_locale_ids" => [annapolis.id],
        "previous_sway_locale_names" => [baltimore.name],
        "new_sway_locale_names" => [annapolis.name],
        "prior_vote_count" => 2,
        "prior_voted_bill_ids" => [501, 502],
        "prior_voted_sway_locale_ids" => [baltimore.id],
        "cross_district" => true,
        "cross_sway_locale" => true,
        "voted_before_switch" => true,
        "user_switch_count" => 2,
        "created_at" => newer_change.created_at.iso8601
      )

      second_row = rows.second.transform_keys(&:to_s)
      expect(second_row).to include(
        "id" => older_change.id,
        "cross_district" => false,
        "cross_sway_locale" => false,
        "voted_before_switch" => false,
        "prior_vote_count" => 0,
        "user_switch_count" => 2
      )
    end

    it "never exposes street or coordinate values in props or response body" do
      previous_address = create(
        :address,
        street: "742 Evergreen Terrace Secret",
        latitude: "39.299999",
        longitude: "-76.619999"
      )
      new_address = create(
        :address,
        street: "999 Confidential Way",
        latitude: "38.888888",
        longitude: "-77.111111"
      )
      create(
        :user_address_change,
        previous_address:,
        new_address:
      )

      get "/admin/user_address_changes"

      expect(inertia).to render_component("admin/UserAddressChanges")
      body_keys = inertia.props[:user_address_changes].flat_map { |row| row.keys.map(&:to_s) }.uniq
      expect(body_keys).not_to include("street", "street2", "street3", "latitude", "longitude")
      expect(response.body).not_to include("742 Evergreen Terrace Secret")
      expect(response.body).not_to include("999 Confidential Way")
      expect(response.body).not_to include("39.299999")
      expect(response.body).not_to include("-76.619999")
      expect(response.body).not_to include("38.888888")
      expect(response.body).not_to include("-77.111111")
    end
  end
end
