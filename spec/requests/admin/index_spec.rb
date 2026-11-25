# frozen_string_literal: true

require "rails_helper"

# @lat: [[admin-hub-and-tabs#Why /admin exists]]
RSpec.describe "Admin::Index", type: :request do
  include_context "SessionDouble"

  include_examples "requires sway admin",
    verb: :get,
    path: "/admin"

  context "with a bearer token and Accept: application/json" do
    let(:api_token) { SecureRandom.hex(32) }
    let(:headers) { {"Authorization" => "Bearer #{api_token}", "Accept" => "application/json"} }

    # @lat: [[admin-hub-index#JSON shape for the mobile app]]
    it "serves the tools list and database health as JSON to a sway admin" do
      ApiKey.create!(bearer: create(:user, :sway_admin), token: api_token)

      get "/admin", headers: headers

      expect(response).to have_http_status(:ok)
      expect(response.media_type).to eq("application/json")
      body = response.parsed_body
      tools = body.fetch("tools")
      expect(tools.map { |tool| tool.fetch("id") }).to include("bill_creator", "partner_reports")
      expect(tools.map(&:keys).flatten.uniq).to include("id", "label", "description", "path", "group", "external")
      expect(body.fetch("database_health")).to include("databases", "solid_queue_ready", "solid_queue_failed")
    end

    # @lat: [[admin-hub-index#JSON shape for the mobile app]]
    it "keeps the extra title and icon keys on the partner_reports tool" do
      ApiKey.create!(bearer: create(:user, :sway_admin), token: api_token)

      get "/admin", headers: headers

      partner_reports = response.parsed_body.fetch("tools").find { |tool| tool["id"] == "partner_reports" }
      expect(partner_reports).to include("title" => "Partner Reports", "icon" => "TrendingUp")
    end

    # @lat: [[admin-hub-index#JSON shape for the mobile app]]
    it "marks the beszel tool external for a sway admin on a listed monitoring domain" do
      ApiKey.create!(bearer: create(:user, :sway_admin, email: "admin@ops.example.org"), token: api_token)

      with_app_config(:ops, beszel_admin_email_domains: ["ops.example.org"]) do
        get "/admin", headers: headers
      end

      beszel = response.parsed_body.fetch("tools").find { |tool| tool["id"] == "beszel" }
      expect(beszel).to include("external" => true, "group" => "Operations")
    end

    it "refuses a non-admin with a forbidden JSON error" do
      user = create(:user)
      create(:user_legislator, user: user)
      user.complete!
      ApiKey.create!(bearer: user, token: api_token)

      get "/admin", headers: headers

      expect(response).to have_http_status(:forbidden)
      expect(response.parsed_body.dig("error", "code")).to eq("forbidden")
    end
  end

  context "as a sway admin" do
    let(:admin) { create(:user, :sway_admin) }

    before { session_hash[:user_id] = admin.id }

    describe "GET /admin" do
      it "renders the admin/Index Inertia page with the tools list" do
        get "/admin"

        expect(response).to have_http_status(:ok)
        expect(inertia).to be_inertia_response
        expect(inertia).to render_component("admin/Index")

        tools = inertia.props[:tools]
        expect(tools).to be_an(Array)
        expect(tools.pluck(:id)).to include(
          "bill_creator", "llm_settings", "pipeline_runs", "system_prompts", "user_address_changes"
        )
        expect(tools.pluck(:path)).to include(
          admin_llm_settings_path,
          new_bill_creator_path,
          pipeline_runs_path,
          admin_system_prompts_path,
          admin_user_address_changes_path
        )

        tools.each do |tool|
          expect(tool).to include(:id, :label, :description, :path, :group, :external)
          expect(tool[:label]).to be_present
          expect(tool[:description]).to be_present
        end
        expect(tools.pluck(:id)).not_to include("beszel")

        db_health = inertia.props[:database_health]
        expect(db_health[:databases]).to be_an(Array)
        expect(db_health[:databases].first).to include(:name, :database_bytes, :wal_bytes)
        expect(db_health[:solid_queue_ready]).to be_a(Integer)
        expect(db_health[:solid_queue_failed]).to be_a(Integer)
        expect(response.headers["Server-Timing"]).to include("sql_queries;desc=")
      end

      # @lat: [[admin-hub-index#Who sees the monitoring link]]
      it "includes the external Beszel tool when the sway admin's email is on a listed monitoring domain" do
        admin.update!(email: "admin@ops.example.org")

        with_app_config(:ops, beszel_admin_email_domains: ["ops.example.org"]) do
          get "/admin"
        end

        expect(response).to have_http_status(:ok)
        expect(inertia).to render_component("admin/Index")

        beszel_tool = inertia.props[:tools].find { |t| t[:id] == "beszel" }
        expect(beszel_tool).to include(
          id: "beszel",
          label: "Beszel",
          path: "http://sway-test.invalid:8090",
          group: "Operations",
          external: true
        )
      end
    end
  end
end
