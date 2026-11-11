# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Admin::BillSummaryReports", type: :request do
  include_context "SessionDouble"
  include_context "Setup"

  let(:sway_locale) { create(:sway_locale) }
  let(:other_locale) { create(:sway_locale) }
  let(:bill) { create(:bill, sway_locale:) }
  let(:other_bill) { create(:bill, sway_locale: other_locale, scheduled_release_date_utc: 3.days.ago) }
  let(:admin) { create(:user, :sway_admin) }
  let(:report) { create(:bill_summary_report, bill:) }

  include_examples "requires sway admin", verb: :get, path: "/admin/bill_summary_reports"
  include_examples "requires sway admin", verb: :patch, path: "/admin/bill_summary_reports/1",
    params: {bill_summary_report: {status: "reviewed"}}

  describe "GET /admin/bill_summary_reports" do
    before do
      session_hash[:user_id] = admin.id
    end

    it "renders the Inertia index page with serialized reports and status counts" do
      create(:bill_summary_report, bill:, status: :pending)
      create(:bill_summary_report, bill:, status: :reviewed, created_at: 2.hours.ago)

      get "/admin/bill_summary_reports"

      expect(response).to have_http_status(:ok)
      expect(inertia).to render_component(Pages::ADMIN_BILL_SUMMARY_REPORTS)
      props = inertia.props
      expect(props[:reports].length).to eq(2)
      expect(props[:status_counts][:pending]).to eq(1)
      expect(props[:status_counts][:reviewed]).to eq(1)
      expect(props[:status_counts][:all]).to eq(2)
    end

    it "filters by status" do
      create(:bill_summary_report, bill:, status: :pending)
      create(:bill_summary_report, bill:, status: :resolved, created_at: 2.hours.ago)

      get "/admin/bill_summary_reports", params: {status: "resolved"}

      expect(response).to have_http_status(:ok)
      expect(inertia.props[:reports].length).to eq(1)
      expect(inertia.props[:reports].first[:status]).to eq("resolved")
    end

    it "filters by locale" do
      create(:bill_summary_report, bill:)
      create(:bill_summary_report, bill: other_bill)

      get "/admin/bill_summary_reports", params: {locale_id: sway_locale.id}

      expect(response).to have_http_status(:ok)
      expect(inertia.props[:reports].length).to eq(1)
      expect(inertia.props[:reports].first[:bill_id]).to eq(bill.id)
    end

    it "returns JSON list when requested with format json" do
      create(:bill_summary_report, bill:)

      get "/admin/bill_summary_reports.json"

      expect(response).to have_http_status(:ok)
      body = response.parsed_body
      expect(body.length).to eq(1)
      expect(body.first["bill_id"]).to eq(bill.id)
    end
  end

  describe "GET /admin/bill_summary_reports/:id" do
    before { session_hash[:user_id] = admin.id }

    it "returns serialized report json" do
      get "/admin/bill_summary_reports/#{report.id}.json"

      expect(response).to have_http_status(:ok)
      body = response.parsed_body
      expect(body["id"]).to eq(report.id)
      expect(body["bill_title"]).to eq(bill.title)
    end
  end

  describe "PATCH /admin/bill_summary_reports/:id" do
    before { session_hash[:user_id] = admin.id }

    it "updates status to reviewed" do
      patch "/admin/bill_summary_reports/#{report.id}", params: {
        bill_summary_report: {status: "reviewed"}
      }

      expect(response).to redirect_to("/admin/bill_summary_reports")
      expect(report.reload.status).to eq("reviewed")
    end

    it "updates status to resolved, sets resolved_by and resolved_at" do
      patch "/admin/bill_summary_reports/#{report.id}", params: {
        bill_summary_report: {
          status: "resolved",
          admin_notes: "Regenerated summary in Bill Creator."
        }
      }

      expect(response).to redirect_to("/admin/bill_summary_reports")
      report.reload
      expect(report.status).to eq("resolved")
      expect(report.resolved_by_id).to eq(admin.id)
      expect(report.resolved_at).to be_present
      expect(report.admin_notes).to eq("Regenerated summary in Bill Creator.")
    end

    it "updates status to dismissed, sets resolved_by and resolved_at" do
      patch "/admin/bill_summary_reports/#{report.id}", params: {
        bill_summary_report: {
          status: "dismissed",
          admin_notes: "Report is inaccurate; summary reflects bill text."
        }
      }

      expect(response).to redirect_to("/admin/bill_summary_reports")
      report.reload
      expect(report.status).to eq("dismissed")
      expect(report.resolved_by_id).to eq(admin.id)
      expect(report.resolved_at).to be_present
    end

    it "returns JSON on JSON patch request" do
      patch "/admin/bill_summary_reports/#{report.id}.json", params: {
        bill_summary_report: {status: "reviewed"}
      }

      expect(response).to have_http_status(:ok)
      body = response.parsed_body
      expect(body["status"]).to eq("reviewed")
    end
  end
end
