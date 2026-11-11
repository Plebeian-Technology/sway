# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Admin::RegistrationFunnel", type: :request do
  include_context "SessionDouble"

  include_examples "requires sway admin",
    verb: :get,
    path: "/admin/registration_funnel"

  context "as a sway admin" do
    let(:admin) { create(:user, :sway_admin) }

    before do
      sign_in(admin)

      RegistrationFunnelEvent.create!(
        visitor_token: "v-adm-1",
        step: :landing,
        attribution_key: "s:campaign",
        created_at: 1.day.ago
      )
      RegistrationFunnelEvent.create!(
        visitor_token: "v-adm-1",
        step: :phone_submitted,
        attribution_key: "s:campaign",
        created_at: 1.day.ago
      )
    end

    it "renders the Inertia registration funnel dashboard" do
      get "/admin/registration_funnel"

      expect(response).to have_http_status(:ok)
      expect(inertia).to render_component("admin/RegistrationFunnel/Index")
      funnel_prop = inertia.props[:funnel]
      expect(funnel_prop).to be_present
      expect(funnel_prop[:time_range]).to eq("30d")
      expect(funnel_prop[:steps]).to be_an(Array)
      expect(funnel_prop[:friction_points]).to be_an(Array)
      expect(funnel_prop[:attributions]).to be_an(Array)
      expect(funnel_prop[:latency]).to be_a(Hash)
    end

    it "supports filtering by time_range" do
      get "/admin/registration_funnel", params: {time_range: "7d"}

      expect(response).to have_http_status(:ok)
      expect(inertia.props[:funnel][:time_range]).to eq("7d")
    end

    it "supports filtering by attribution_key" do
      get "/admin/registration_funnel", params: {attribution_key: "s:campaign"}

      expect(response).to have_http_status(:ok)
      expect(inertia.props[:funnel][:filter_attribution_key]).to eq("s:campaign")
    end

    # @lat: [[registration-funnel-telemetry#Bot traffic classification#Traffic filter on the admin dashboard]]
    it "supports filtering by traffic" do
      get "/admin/registration_funnel", params: {traffic: "bots"}

      expect(response).to have_http_status(:ok)
      expect(inertia.props[:funnel][:traffic]).to eq("bots")
    end

    it "responds to JSON format request" do
      get "/admin/registration_funnel", headers: {"Accept" => "application/json"}

      expect(response).to have_http_status(:ok)
      json = response.parsed_body
      expect(json).to include("time_range", "steps", "friction_points", "attributions", "latency")
    end
  end
end
