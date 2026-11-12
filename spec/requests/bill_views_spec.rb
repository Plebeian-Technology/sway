# frozen_string_literal: true

require "rails_helper"

RSpec.describe "BillView recording", type: :request do
  include_context "SessionDouble"
  include_context "Setup"

  let!(:sway_locale_and_user) { setup }
  let(:sway_locale) { sway_locale_and_user.first }
  let(:user) { sway_locale_and_user.last }
  let(:legislator) { sway_locale.legislators.first }
  let(:bill) { create(:bill, sway_locale:, legislator:) }

  describe "GET /bills/:id" do
    it "records one view on a signed-in user's first visit and none on the second" do
      expect { get "/bills/#{bill.id}" }.to change(BillView, :count).by(1)
      expect(response).to have_http_status(:ok)

      expect { get "/bills/#{bill.id}" }.not_to change(BillView, :count)
      expect(response).to have_http_status(:ok)
    end

    it "records one view on a bearer-authenticated JSON request and none on the second" do
      sign_out
      raw_token = "test-bearer-token-#{SecureRandom.hex(8)}"
      ApiKey.create!(bearer: user, token: raw_token)
      headers = {"Authorization" => "Bearer #{raw_token}", "Accept" => "application/json"}

      expect { get "/bills/#{bill.id}", headers: }.to change(BillView, :count).by(1)
      expect(response).to have_http_status(:ok)

      expect { get "/bills/#{bill.id}", headers: }.not_to change(BillView, :count)
      expect(response).to have_http_status(:ok)
    end

    it "skips Inertia partial reloads" do
      headers = {
        "X-Inertia" => "true",
        "X-Inertia-Version" => InertiaRails.configuration.version.to_s,
        "X-Inertia-Partial-Component" => Pages::BILL,
        "X-Inertia-Partial-Data" => "bill_score"
      }

      expect { get "/bills/#{bill.id}", headers: }.not_to change(BillView, :count)
      expect(response).to have_http_status(:ok)
    end

    it "skips Purpose and Sec-Purpose prefetch requests" do
      expect { get "/bills/#{bill.id}", headers: {"Purpose" => "prefetch"} }.not_to change(BillView, :count)
      expect(response).to have_http_status(:ok)

      expect { get "/bills/#{bill.id}", headers: {"Sec-Purpose" => "prefetch"} }.not_to change(BillView, :count)
      expect(response).to have_http_status(:ok)
    end

    it "skips anonymous visits" do
      sign_out

      expect { get "/bills/#{bill.id}" }.not_to change(BillView, :count)
      expect(response).to have_http_status(:ok)
    end
  end

  describe "GET /bill_of_the_month" do
    context "when a featured bill exists" do
      before do
        create(:bill, sway_locale:, legislator:, scheduled_release_date_utc: Time.zone.today)
      end

      it "records one view on a signed-in user's first visit and none on the second" do
        featured_bill = Bill.of_the_month(sway_locale:)
        expect { get "/bill_of_the_month" }.to change(BillView, :count).by(1)
        expect(response).to have_http_status(:ok)
        expect(BillView.last!.bill_id).to eq(featured_bill&.id)

        expect { get "/bill_of_the_month" }.not_to change(BillView, :count)
        expect(response).to have_http_status(:ok)
      end

      it "records one view on a bearer-authenticated JSON request" do
        sign_out
        raw_token = "test-bearer-token-#{SecureRandom.hex(8)}"
        ApiKey.create!(bearer: user, token: raw_token)
        headers = {"Authorization" => "Bearer #{raw_token}", "Accept" => "application/json"}

        expect { get "/bill_of_the_month", headers: }.to change(BillView, :count).by(1)
        expect(response).to have_http_status(:ok)
      end

      it "skips Inertia partial reloads and prefetch requests" do
        partial_headers = {
          "X-Inertia" => "true",
          "X-Inertia-Version" => InertiaRails.configuration.version.to_s,
          "X-Inertia-Partial-Component" => Pages::BILL_OF_THE_MONTH,
          "X-Inertia-Partial-Data" => "bill_score"
        }

        expect { get "/bill_of_the_month", headers: partial_headers }.not_to change(BillView, :count)
        expect { get "/bill_of_the_month", headers: {"Purpose" => "prefetch"} }.not_to change(BillView, :count)
        expect { get "/bill_of_the_month", headers: {"Sec-Purpose" => "prefetch"} }.not_to change(BillView, :count)
      end

      it "skips anonymous visits" do
        sign_out

        expect { get "/bill_of_the_month" }.not_to change(BillView, :count)
        expect(response).to have_http_status(:ok)
      end
    end

    context "when no featured bill exists" do
      it "creates no rows" do
        expect { get "/bill_of_the_month" }.not_to change(BillView, :count)
        expect(response).to have_http_status(:ok)
      end
    end
  end
end
