# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Admin::PartnerReports", type: :request do
  # @lat: [[partner-article-engagement#Administrative interface]]
  include_context "SessionDouble"
  include_context "Setup"

  let(:sway_locale) { create(:sway_locale) }
  let(:admin) { create(:user, :sway_admin) }
  let(:org) { create(:organization, sway_locale:, name: "The Baltimore Banner") }
  let(:bill) { create(:bill, sway_locale:) }

  include_examples "requires sway admin", verb: :get, path: "/admin/partner_reports"

  describe "GET /admin/partner_reports" do
    before do
      session_hash[:user_id] = admin.id
      ArticleBill.create!(
        bill:,
        organization: org,
        partner_slug: "the-banner",
        article_url: "https://thebaltimorebanner.com/story/1",
        article_title: "Banner Bill Coverage",
        clicks_count: 50,
        registrations_count: 10,
        votes_count: 8,
        pro_votes_count: 6,
        con_votes_count: 2
      )
    end

    it "renders the Inertia index page with partner reports list" do
      get "/admin/partner_reports"

      expect(response).to have_http_status(:ok)
      expect(inertia).to render_component(Pages::ADMIN_PARTNER_REPORTS)
      props = inertia.props
      expect(props[:reports].length).to eq(1)
      expect(props[:reports].first[:partner_slug]).to eq("the-banner")
      expect(props[:reports].first[:total_clicks]).to eq(50)
      expect(props[:reports].first[:total_votes]).to eq(8)
    end

    it "responds with JSON for JSON requests" do
      get "/admin/partner_reports", headers: {"Accept" => "application/json"}

      expect(response).to have_http_status(:ok)
      body = response.parsed_body
      expect(body.length).to eq(1)
      expect(body.first["partner_slug"]).to eq("the-banner")
      expect(body.first["total_clicks"]).to eq(50)
    end
  end

  describe "GET /admin/partner_reports/:id" do
    before do
      session_hash[:user_id] = admin.id
      ArticleBill.create!(
        bill:,
        organization: org,
        partner_slug: "the-banner",
        article_url: "https://thebaltimorebanner.com/story/1",
        article_title: "Banner Bill Coverage",
        clicks_count: 50,
        registrations_count: 10,
        votes_count: 8,
        pro_votes_count: 6,
        con_votes_count: 2
      )
    end

    it "renders the report by organization ID" do
      get "/admin/partner_reports/#{org.id}"

      expect(response).to have_http_status(:ok)
      expect(inertia).to render_component(Pages::ADMIN_PARTNER_REPORTS)
      report = inertia.props[:report]
      expect(report[:partner_slug]).to eq("the-banner")
      expect(report[:articles].length).to eq(1)
    end

    it "renders the report by partner_slug" do
      get "/admin/partner_reports/the-banner"

      expect(response).to have_http_status(:ok)
      expect(inertia).to render_component(Pages::ADMIN_PARTNER_REPORTS)
      report = inertia.props[:report]
      expect(report[:partner_slug]).to eq("the-banner")
      expect(report[:total_votes]).to eq(8)
    end

    it "responds with JSON for JSON requests" do
      get "/admin/partner_reports/#{org.id}", headers: {"Accept" => "application/json"}

      expect(response).to have_http_status(:ok)
      body = response.parsed_body
      expect(body["partner_slug"]).to eq("the-banner")
      expect(body["total_registrations"]).to eq(10)
    end
  end
end
