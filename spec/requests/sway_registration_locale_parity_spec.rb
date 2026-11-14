# frozen_string_literal: true

# @lat: [[sway-registration-controller-notes#What AddressScreen.parity.test.tsx deliberately does not cover]]

require "rails_helper"
require Rails.root.join("db", "seeds", "models", "sway_locale")
require Rails.root.join("db", "seeds", "models", "legislator")

RSpec.describe "POST /sway_registration locale parity", type: :request do
  include_context "SessionDouble"

  let!(:user) { create(:user, is_registration_complete: false, registration_status: "pending") }
  let(:annapolis) { SwayLocale.resolve_by_computed_name("annapolis-maryland-united_states") || raise("Annapolis not seeded") }
  let(:maryland) { SwayLocale.resolve_by_computed_name("maryland-maryland-united_states") || raise("Maryland not seeded") }
  let(:congress) { SwayLocale.resolve_by_computed_name("congress-congress-united_states") || raise("Congress not seeded") }

  before do
    SeedSwayLocale.run
    SeedLegislator.run([annapolis, maryland, congress])
  end

  def stub_census_district(number)
    stub_request(:get, %r{tigerweb\.geo\.census\.gov/arcgis/rest/services/TIGERweb/})
      .to_return(status: 200, body: {features: [{attributes: {"CD#{Census::CURRENT_CONGRESS_NUMBER}" => number}}]}.to_json)
  end

  def stub_open_states_delegation(delegation)
    stub_request(:get, %r{v3\.openstates\.org/people\.geo})
      .to_return(
        status: 200,
        body: {results: delegation.map { |legislator| {id: legislator.external_id, jurisdiction: {name: "Maryland"}} }}.to_json,
        headers: {"Content-Type" => "application/json"}
      )
  end

  def current_members(sway_locale, *district_names)
    sway_locale.legislators.with_active_term.select { |legislator| district_names.include?(legislator.active_term.district.name) }
  end

  def maryland_members(*full_names)
    full_names.map do |full_name|
      first_name, last_name = full_name.split
      maryland.legislators.find_by!(first_name:, last_name:)
    end
  end

  def maryland_governor
    maryland_members("Wes Moore").first
  end

  def register_from(client, address_params)
    with_env("OPEN_STATES_API_KEY" => "test-open-states-key") do
      if client == :web
        sign_in(user)
        post "/sway_registration", params: {sway_registration: address_params}
        expect(response).to redirect_to(feed_path)
      else
        post "/sway_registration", params: {sway_registration: address_params}, headers: authenticate_as(user)
        expect(response).to have_http_status(:ok)
        expect(response.parsed_body).to eq({"ok" => true, "registration_status" => "completed"})
      end
    end
  end

  def expect_completed_with(legislators)
    expect(user.reload.registration_status).to eq("completed")
    expect(UserLegislator.where(user:, active: true).pluck(:legislator_id)).to match_array(legislators.map(&:id))
  end

  [:web, :bearer].each do |client|
    context "with the #{client} client" do
      it "links the Annapolis officers, the Maryland Governor and delegation, and the Congress members for an Annapolis address" do
        delegation = maryland_members("Shaneka Henson", "Dana Jones", "Dylan Behler")
        stub_open_states_delegation(delegation)
        stub_census_district("03")

        register_from(client, {
          street: "160 Duke of Gloucester St",
          city: "Annapolis",
          region_code: "MD",
          postal_code: "21401",
          country: "United States",
          latitude: 38.9784,
          longitude: -76.4922
        })

        annapolis_officers = annapolis.legislators.where(external_id: ["annapolis-mayor", "annapolis-ward-1"]).to_a
        congress_members = current_members(congress, "MD0", "MD3")
        expect(congress_members.map(&:title)).to contain_exactly("Sen.", "Sen.", "Rep.")
        expect_completed_with(annapolis_officers + [maryland_governor] + delegation + congress_members)
      end

      it "links Maryland and Congress members and no city officer for a Towson address" do
        delegation = maryland_members("Chris West", "Nino Mangione")
        stub_open_states_delegation(delegation)
        stub_census_district("02")

        register_from(client, {
          street: "400 Washington Ave",
          city: "Towson",
          region_code: "MD",
          postal_code: "21204",
          country: "United States",
          latitude: 39.4015,
          longitude: -76.6019
        })

        congress_members = current_members(congress, "MD0", "MD2")
        expect(congress_members.map(&:title)).to contain_exactly("Sen.", "Sen.", "Rep.")
        expect_completed_with([maryland_governor] + delegation + congress_members)
      end

      it "links only the Virginia Congress members for a Richmond address" do
        stub_census_district("04")

        register_from(client, {
          street: "900 E Broad St",
          city: "Richmond",
          region_code: "VA",
          postal_code: "23219",
          country: "United States",
          latitude: 37.5407,
          longitude: -77.4336
        })

        virginia_members = current_members(congress, "VA0", "VA4")
        expect(virginia_members.map(&:title)).to contain_exactly("Sen.", "Sen.", "Rep.")
        expect_completed_with(virginia_members)
      end
    end
  end
end
