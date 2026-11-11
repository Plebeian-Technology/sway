# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Admin::SharedAddresses", type: :request do
  include_context "SessionDouble"

  include_examples "requires sway admin",
    verb: :get,
    path: "/admin/shared_addresses"

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
