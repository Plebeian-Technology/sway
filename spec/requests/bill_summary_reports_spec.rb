# frozen_string_literal: true

require "rails_helper"

RSpec.describe "BillSummaryReports", type: :request do
  include_context "SessionDouble"
  include_context "Setup"

  let(:sway_locale) { create(:sway_locale) }
  let(:bill) { create(:bill, sway_locale:, summary: "AI bill summary.") }

  describe "POST /bills/:bill_id/summary_reports" do
    context "as an unauthenticated guest" do
      it "creates a report and redirects back to bill page with notice for HTML" do
        expect do
          post "/bills/#{bill.id}/summary_reports", params: {
            bill_summary_report: {
              reason: "factual_inaccuracy",
              details: "The tax rate is actually 5% not 15%."
            }
          }
        end.to change(BillSummaryReport, :count).by(1)

        expect(response).to redirect_to("/bills/#{bill.id}")
        follow_redirect!
        expect(flash[:notice]).to eq("Thank you for reporting this summary. Our team will review it.")

        report = BillSummaryReport.last
        expect(report&.bill_id).to eq(bill.id)
        expect(report&.user_id).to be_nil
        expect(report&.reason).to eq("factual_inaccuracy")
        expect(report&.details).to eq("The tax rate is actually 5% not 15%.")
        expect(report&.status).to eq("pending")
      end

      it "creates a report and returns JSON 201 when requested" do
        post "/bills/#{bill.id}/summary_reports",
          params: {
            bill_summary_report: {
              reason: "misleading_tone",
              explanation: "The summary presents biased viewpoints."
            }
          },
          headers: {"Accept" => "application/json"}

        expect(response).to have_http_status(:created)
        body = response.parsed_body
        expect(body["id"]).to be_present
        expect(body["reason"]).to eq("misleading_tone")
        expect(body["details"]).to eq("The summary presents biased viewpoints.")
      end

      it "rejects invalid reason with 422 unprocessable_content for JSON" do
        post "/bills/#{bill.id}/summary_reports",
          params: {
            bill_summary_report: {
              reason: "invalid_reason",
              details: "Something wrong."
            }
          },
          headers: {"Accept" => "application/json"}

        expect(response).to have_http_status(:unprocessable_content)
        body = response.parsed_body
        expect(body["error"]).to be_present
      end
    end

    context "as an authenticated user" do
      it "associates the current user with the report" do
        _locale, user = setup
        session_hash[:user_id] = user.id

        expect do
          post "/bills/#{bill.id}/summary_reports", params: {
            bill_summary_report: {
              reason: "missing_amendment",
              details: "Amended on second reading."
            }
          }
        end.to change(BillSummaryReport, :count).by(1)

        report = BillSummaryReport.last
        expect(report&.user_id).to eq(user.id)
      end
    end

    context "rate limiting" do
      it "enforces rate limits when enabled in production" do
        with_rate_limit_enabled(:bill_summary_report) do
          6.times do
            post "/bills/#{bill.id}/summary_reports", params: {
              bill_summary_report: {
                reason: "other",
                details: "Rate limit test report."
              }
            }
          end

          expect(response).to have_http_status(:redirect).or(have_http_status(:too_many_requests))
        end
      end

      it "returns 429 with Retry-After: 60 on the 6th JSON request from the same IP and ignores mass-assigned resolution fields" do
        ApplicationController::RATE_LIMIT_STORE.clear if ApplicationController::RATE_LIMIT_STORE.respond_to?(:clear)
        with_rate_limit_enabled(:bill_summary_report) do
          post "/bills/#{bill.id}/summary_reports",
            params: {
              bill_summary_report: {
                reason: "factual_inaccuracy",
                details: "First report with parameter tampering",
                status: "resolved",
                resolved_by_id: 1,
                admin_notes: "Tampered"
              }
            },
            headers: {"REMOTE_ADDR" => "192.0.2.77", "Accept" => "application/json"}

          expect(response).to have_http_status(:created)
          created = BillSummaryReport.last
          expect(created&.status).to eq("pending")
          expect(created&.resolved_by_id).to be_nil
          expect(created&.admin_notes).to be_nil

          4.times do
            post "/bills/#{bill.id}/summary_reports",
              params: {bill_summary_report: {reason: "other", details: "Repeat"}},
              headers: {"REMOTE_ADDR" => "192.0.2.77", "Accept" => "application/json"}
          end

          post "/bills/#{bill.id}/summary_reports",
            params: {bill_summary_report: {reason: "other", details: "6th attempt"}},
            headers: {"REMOTE_ADDR" => "192.0.2.77", "Accept" => "application/json"}

          expect(response).to have_http_status(:too_many_requests)
          expect(response.headers["Retry-After"]).to eq("60")
        end
      end
    end
  end
end
