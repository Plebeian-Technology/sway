# frozen_string_literal: true

require "rails_helper"

# @lat: [[bill-creator-tab-url-routing#Why the legacy redirects have their own request-spec contract, not just implicit coverage]]
RSpec.describe "Legacy Bill Creator URL redirects", type: :request do
  describe "GET /bills/new" do
    it "302s (not 301) to /admin/bill_creator/new" do
      get "/bills/new"
      expect(response).to have_http_status(:found)
      expect(response.location).to end_with("/admin/bill_creator/new")
    end

    it "preserves the query string so tab_key + event_key + sway_locale_id survive the hop" do
      get "/bills/new", params: {tab_key: "summary", event_key: "bill", sway_locale_id: "3"}
      expect(response.location).to include("tab_key=summary")
      expect(response.location).to include("event_key=bill")
      expect(response.location).to include("sway_locale_id=3")
    end
  end

  describe "GET /bills/:id/edit" do
    it "302s (not 301) to /admin/bill_creator/:id/edit" do
      get "/bills/42/edit"
      expect(response).to have_http_status(:found)
      expect(response.location).to end_with("/admin/bill_creator/42/edit")
    end

    it "preserves the query string for tab_key + sway_locale_id + saved" do
      get "/bills/42/edit", params: {tab_key: "pipeline_llm", sway_locale_id: "3", saved: "Bill Created"}
      expect(response.location).to include("/admin/bill_creator/42/edit?")
      expect(response.location).to include("tab_key=pipeline_llm")
      expect(response.location).to include("sway_locale_id=3")
      # `saved` has a space in its real-world value — URL-encoded as a + or %20.
      expect(response.location).to match(/saved=(Bill\+Created|Bill%20Created)/)
    end
  end

  # @lat: [[bill-creator-tab-url-routing#Why the legacy redirects have their own request-spec contract, not just implicit coverage]]
  describe "named path helpers (F-i2-WR-003)" do
    # Request specs pull in Rails.application.routes.url_helpers, so the path
    # helpers can be called here directly by name.
    it "new_bill_path resolves to /bills/new" do
      expect(new_bill_path).to eq("/bills/new")
    end

    it "edit_bill_path resolves to /bills/:id/edit" do
      expect(edit_bill_path(42)).to eq("/bills/42/edit")
    end
  end
end
