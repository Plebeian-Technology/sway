# frozen_string_literal: true

require "rails_helper"

# @lat: [[admin-hub-and-tabs#Why /admin exists]]
RSpec.describe "Admin::Index", type: :request do
  include_context "SessionDouble"

  include_examples "requires sway admin",
    verb: :get,
    path: "/admin"

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
