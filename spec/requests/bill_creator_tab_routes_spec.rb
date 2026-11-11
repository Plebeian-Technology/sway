# frozen_string_literal: true

require "rails_helper"

# @lat: [[bill-creator-shell#The Bill Creator shell#Why tab URLs retain legacy compatibility]]
RSpec.describe "Bill Creator tab routes (follow-up A)", type: :request do
  include_context "SessionDouble"

  let(:admin) { create(:user, :sway_admin) }
  let(:bill) { create(:bill) }

  before { session_hash[:user_id] = admin.id }

  describe "new-page query compatibility" do
    it "reads the canonical bill_creator_tab query key" do
      get "/admin/bill_creator/new?bill_creator_tab=summary&tab_key=creator"

      expect(response).to have_http_status(:ok)
      expect(inertia.props[:tab_key]).to eq("summary")
    end

    it "still reads the legacy tab_key query key when canonical is absent" do
      get "/admin/bill_creator/new?tab_key=summary"

      expect(response).to have_http_status(:ok)
      expect(inertia.props[:tab_key]).to eq("summary")
    end

    it "does not revive the legacy value when the canonical key is explicitly empty" do
      get "/admin/bill_creator/new?bill_creator_tab=&tab_key=summary"

      expect(response).to have_http_status(:ok)
      expect(inertia.props[:tab_key]).to eq("")
    end
  end

  describe "canonical tab-segment routes" do
    %w[creator schedule pipeline summary positions].each do |tab|
      it "GET /admin/bill_creator/:id/#{tab} renders bills#edit with tab_key=#{tab}" do
        get "/admin/bill_creator/#{bill.id}/#{tab}"

        expect(response).to have_http_status(:ok)
        expect(inertia).to be_inertia_response
        expect(inertia).to render_component(Pages::BILL_CREATOR)
        expect(inertia.props[:tab_key]).to eq(tab)
      end
    end

    it "keeps the path tab authoritative over disagreeing canonical and legacy query values" do
      get "/admin/bill_creator/#{bill.id}/pipeline?bill_creator_tab=summary&tab_key=creator"

      expect(response).to have_http_status(:ok)
      expect(inertia.props[:tab_key]).to eq("pipeline")
    end

    it "does not serve a page for an unknown tab segment" do
      # @lat: [[bill-creator-shell#The Bill Creator shell#Why tab URLs retain legacy compatibility]]
      get "/admin/bill_creator/#{bill.id}/not_a_tab"

      expect(response).to have_http_status(:not_found)
    end
  end

  describe "bare id redirect" do
    it "GET /admin/bill_creator/:id 302s to /:id/creator (the default tab)" do
      get "/admin/bill_creator/#{bill.id}"

      expect(response).to have_http_status(:found)
      expect(response.location).to end_with("/admin/bill_creator/#{bill.id}/creator")
    end

    it "preserves query params on the bare-id redirect" do
      get "/admin/bill_creator/#{bill.id}", params: {sway_locale_id: "3", saved: "Bill Created"}

      expect(response.location).to include("/admin/bill_creator/#{bill.id}/creator?")
      expect(response.location).to include("sway_locale_id=3")
      expect(response.location).to match(/saved=(Bill\+Created|Bill%20Created)/)
    end
  end

  describe "legacy /:id/edit?tab_key= redirect" do
    %w[creator schedule pipeline summary positions].each do |tab|
      it "GET /admin/bill_creator/:id/edit?tab_key=#{tab} 302s to /:id/#{tab}" do
        get "/admin/bill_creator/#{bill.id}/edit", params: {tab_key: tab}

        expect(response).to have_http_status(:found)
        expect(response.location).to end_with("/admin/bill_creator/#{bill.id}/#{tab}")
      end
    end

    it "translates legacy ETab value 'pipeline_llm' to /:id/pipeline (post-sweep)" do
      get "/admin/bill_creator/#{bill.id}/edit", params: {tab_key: "pipeline_llm"}

      expect(response).to have_http_status(:found)
      expect(response.location).to end_with("/admin/bill_creator/#{bill.id}/pipeline")
    end

    it "prefers the canonical query key over legacy tab_key" do
      get "/admin/bill_creator/#{bill.id}/edit?bill_creator_tab=summary&tab_key=creator"

      expect(response).to have_http_status(:found)
      expect(response.location).to end_with("/admin/bill_creator/#{bill.id}/summary")
    end

    it "does not revive a legacy tab when the canonical query key is explicitly empty" do
      get "/admin/bill_creator/#{bill.id}/edit?bill_creator_tab=&tab_key=summary"

      expect(response).to have_http_status(:found)
      expect(response.location).to end_with("/admin/bill_creator/#{bill.id}/creator")
    end

    it "defaults to /:id/creator when tab_key is missing" do
      get "/admin/bill_creator/#{bill.id}/edit"

      expect(response).to have_http_status(:found)
      expect(response.location).to end_with("/admin/bill_creator/#{bill.id}/creator")
    end

    it "defaults to /:id/creator when tab_key is unknown" do
      get "/admin/bill_creator/#{bill.id}/edit", params: {tab_key: "garbage"}

      expect(response).to have_http_status(:found)
      expect(response.location).to end_with("/admin/bill_creator/#{bill.id}/creator")
    end

    it "drops tab_key from the redirected URL but keeps every other query param" do
      get "/admin/bill_creator/#{bill.id}/edit",
        params: {tab_key: "summary", sway_locale_id: "3", saved: "Bill Updated"}

      expect(response.location).to include("/admin/bill_creator/#{bill.id}/summary?")
      expect(response.location).not_to include("tab_key=")
      expect(response.location).to include("sway_locale_id=3")
      expect(response.location).to match(/saved=(Bill\+Updated|Bill%20Updated)/)
    end
  end

  describe "named path helpers" do
    # Each tab gets its own helper, so code can say `schedule_bill_creator_path(bill)`
    # rather than every caller passing a `:tab` argument by hand. It reads the way the
    # old `edit_bill_creator_path` did, while the URL now carries the tab in its path.
    it "creator_bill_creator_path resolves to /:id/creator" do
      expect(creator_bill_creator_path(id: 42)).to eq("/admin/bill_creator/42/creator")
    end

    it "schedule_bill_creator_path resolves to /:id/schedule" do
      expect(schedule_bill_creator_path(id: 42)).to eq("/admin/bill_creator/42/schedule")
    end

    it "pipeline_bill_creator_path resolves to /:id/pipeline" do
      expect(pipeline_bill_creator_path(id: 42)).to eq("/admin/bill_creator/42/pipeline")
    end

    it "summary_bill_creator_path resolves to /:id/summary" do
      expect(summary_bill_creator_path(id: 42)).to eq("/admin/bill_creator/42/summary")
    end

    # @lat: [[bill-creator-positions-tab#Why positions are a tab of their own]]
    it "positions_bill_creator_path resolves to /:id/positions" do
      expect(positions_bill_creator_path(id: 42)).to eq("/admin/bill_creator/42/positions")
    end
  end

  # Every one of these tab routes has to require a Sway admin.
  include_examples "requires sway admin",
    verb: :get,
    path: "/admin/bill_creator/1/creator"
  include_examples "requires sway admin",
    verb: :get,
    path: "/admin/bill_creator/1/schedule"
  include_examples "requires sway admin",
    verb: :get,
    path: "/admin/bill_creator/1/pipeline"
  include_examples "requires sway admin",
    verb: :get,
    path: "/admin/bill_creator/1/summary"
  include_examples "requires sway admin",
    verb: :get,
    path: "/admin/bill_creator/1/positions"
end
