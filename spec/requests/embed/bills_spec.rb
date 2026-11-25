# frozen_string_literal: true

require "rails_helper"

# @lat: [[embeddable-bill-widget#Embeddable bill widget#Request verification]]
RSpec.describe "Embed::Bills", type: :request do
  include_context "SessionDouble"
  include_context "Setup"
  include ActiveSupport::Testing::TimeHelpers

  let!(:sway_locale) { setup.first }
  let!(:bill) do
    create(
      :bill,
      sway_locale: sway_locale,
      external_id: "SB-123",
      title: "Clean Water and Community Health Act",
      summary: "An act to protect municipal watersheds and improve tap water quality across the state.\n\nAdditional details on standards and penalties."
    )
  end
  let!(:bill_score) { create(:bill_score, bill: bill, for: 25, against: 5) }

  describe "GET /embed/bills/:id" do
    it "returns 200 OK and renders the embed/BillCard Inertia page" do
      get "/embed/bills/#{bill.id}"

      expect(response).to have_http_status(:ok)
      expect(inertia).to render_component(Pages::EMBED_BILL)
      expect(inertia.props[:bill][:id]).to eq(bill.id)
      expect(inertia.props[:bill][:identifier]).to eq("SB-123")
      expect(inertia.props[:bill][:title]).to eq("Clean Water and Community Health Act")
      expect(inertia.props[:bill][:pro_count]).to eq(25)
      expect(inertia.props[:bill][:con_count]).to eq(5)
      expect(inertia.props[:bill][:total_votes]).to eq(30)
      expect(inertia.props[:cta_url]).to eq("/bills/#{bill.id}")
    end

    # @lat: [[voter-privacy-threshold#The embed widget withholds counts on the server]]
    it "withholds the For and Against counts while the bill has nine votes" do
      bill_score.update!(for: 6, against: 3)

      get "/embed/bills/#{bill.id}"

      expect(inertia.props[:bill]).to include(
        pro_count: nil,
        con_count: nil,
        comparison_suppressed: true,
        voters_needed: 1,
        total_votes: 9
      )
      expect(response.body).not_to match(/pro_count&quot;:\s*6|con_count&quot;:\s*3/)
    end

    it "sends the counts and the two flags once the bill has ten votes" do
      bill_score.update!(for: 7, against: 3)

      get "/embed/bills/#{bill.id}"

      expect(inertia.props[:bill]).to include(
        pro_count: 7,
        con_count: 3,
        comparison_suppressed: false,
        voters_needed: 0,
        total_votes: 10
      )
    end

    it "sets public CDN caching headers with s-maxage and stale-while-revalidate" do
      get "/embed/bills/#{bill.id}"

      cache_control = response.headers["Cache-Control"]
      expect(cache_control).to include("public")
      expect(cache_control).to include("max-age=60")
      expect(cache_control).to include("s-maxage=300")
      expect(cache_control).to include("stale-while-revalidate=600")
    end

    it "sets CSP frame-ancestors to permit cross-origin framing while preserving full CSP directives and removing X-Frame-Options" do
      get "/embed/bills/#{bill.id}"

      csp = response.headers["Content-Security-Policy"]
      expect(csp).to include("frame-ancestors *")
      expect(csp).to include("default-src 'self'")
      expect(csp).to include("script-src")
      expect(csp).to include("object-src 'none'")
      expect(response.headers["X-Frame-Options"]).to be_nil
    end

    it "emits zero session cookies (no Set-Cookie header) and does not render csrf meta tags" do
      get "/embed/bills/#{bill.id}"

      expect(response.headers["Set-Cookie"]).to be_nil
      expect(response.body).not_to include('name="csrf-token"')
      expect(response.body).not_to include('name="csrf-param"')
    end

    it "generates distinct ETags for HTML vs X-Inertia requests and includes X-Inertia in Vary" do
      get "/embed/bills/#{bill.id}"
      expect(response).to have_http_status(:ok)
      html_etag = response.headers["ETag"]
      expect(response.headers["Vary"]).to include("X-Inertia")

      get "/embed/bills/#{bill.id}", headers: {
        "X-Inertia" => "true",
        "X-Inertia-Version" => InertiaRails.configuration.version.to_s
      }
      expect(response).to have_http_status(:ok)
      inertia_etag = response.headers["ETag"]

      expect(html_etag).to be_present
      expect(inertia_etag).to be_present
      expect(html_etag).not_to eq(inertia_etag)
    end

    it "forwards partner and referral parameters into the CTA URL" do
      get "/embed/bills/#{bill.id}", params: {partner: "the-banner", ref: "banner-art-42", utm_source: "article"}

      cta_url = inertia.props[:cta_url]
      expect(cta_url).to include("/bills/#{bill.id}")
      expect(cta_url).to include("partner=the-banner")
      expect(cta_url).to include("ref=banner-art-42")
      expect(cta_url).to include("utm_source=article")
    end

    it "returns 304 Not Modified when ETag matches conditional GET" do
      get "/embed/bills/#{bill.id}"
      expect(response).to have_http_status(:ok)
      etag = response.headers["ETag"]
      expect(etag).to be_present

      get "/embed/bills/#{bill.id}", headers: {"If-None-Match" => etag}
      expect(response).to have_http_status(:not_modified)
      expect(response.body).to be_empty
    end

    # @lat: [[voter-privacy-threshold#The embed widget withholds counts on the server]]
    it "changes the ETag when the payload version changes" do
      get "/embed/bills/#{bill.id}"
      etag = response.headers["ETag"]

      stub_const("Embed::BillsController::PAYLOAD_VERSION", "next")
      get "/embed/bills/#{bill.id}"

      expect(response.headers["ETag"]).not_to eq(etag)
    end

    # @lat: [[voter-privacy-threshold#The embed widget withholds counts on the server]]
    it "answers a conditional GET holding a pre-change ETag with the suppressed body" do
      bill_score.update!(for: 6, against: 3)
      stub_const("Embed::BillsController::PAYLOAD_VERSION", "before")
      get "/embed/bills/#{bill.id}"
      old_etag = response.headers["ETag"]

      stub_const("Embed::BillsController::PAYLOAD_VERSION", "after")
      get "/embed/bills/#{bill.id}", headers: {"If-None-Match" => old_etag}

      expect(response).to have_http_status(:ok)
      expect(inertia.props[:bill]).to include(pro_count: nil, con_count: nil, comparison_suppressed: true)
    end

    it "generates different ETags when utm_* parameters differ" do
      get "/embed/bills/#{bill.id}?partner=the-banner&utm_source=twitter"
      expect(response).to have_http_status(:ok)
      etag_twitter = response.headers["ETag"]

      get "/embed/bills/#{bill.id}?partner=the-banner&utm_source=newsletter"
      expect(response).to have_http_status(:ok)
      etag_newsletter = response.headers["ETag"]

      expect(etag_twitter).to be_present
      expect(etag_newsletter).to be_present
      expect(etag_twitter).not_to eq(etag_newsletter)

      get "/embed/bills/#{bill.id}?partner=the-banner&utm_source=newsletter", headers: {"If-None-Match" => etag_twitter}
      expect(response).to have_http_status(:ok)
    end

    it "generates identical ETags regardless of parameter ordering" do
      get "/embed/bills/#{bill.id}?partner=the-banner&utm_source=twitter"
      etag1 = response.headers["ETag"]

      get "/embed/bills/#{bill.id}?utm_source=twitter&partner=the-banner"
      etag2 = response.headers["ETag"]

      expect(etag1).to eq(etag2)
    end

    it "busts ETag and returns 200 OK when bill_score updates even if bill.updated_at is untouched" do
      get "/embed/bills/#{bill.id}"
      expect(response).to have_http_status(:ok)
      original_etag = response.headers["ETag"]
      original_last_modified = response.headers["Last-Modified"]

      original_bill_updated_at = bill.updated_at
      travel_to(1.hour.from_now) do
        bill_score.update_columns(for: 100, against: 20, updated_at: Time.current)
        expect(bill.reload.updated_at).to eq(original_bill_updated_at)

        get "/embed/bills/#{bill.id}", headers: {
          "If-None-Match" => original_etag,
          "If-Modified-Since" => original_last_modified
        }

        expect(response).to have_http_status(:ok)
        expect(response.headers["ETag"]).not_to eq(original_etag)
        expect(inertia.props[:bill][:pro_count]).to eq(100)
        expect(inertia.props[:bill][:con_count]).to eq(20)
        expect(inertia.props[:bill][:total_votes]).to eq(120)
      end
    end

    it "returns 304 Not Modified when both ETag and Last-Modified match" do
      get "/embed/bills/#{bill.id}"
      expect(response).to have_http_status(:ok)
      etag = response.headers["ETag"]
      last_modified = response.headers["Last-Modified"]

      expect(etag).to be_present
      expect(last_modified).to be_present

      get "/embed/bills/#{bill.id}", headers: {
        "If-None-Match" => etag,
        "If-Modified-Since" => last_modified
      }

      expect(response).to have_http_status(:not_modified)
      expect(response.body).to be_empty
    end

    it "returns 200 OK on If-Modified-Since if bill_score has updated" do
      original_bill_updated_at = bill.updated_at
      get "/embed/bills/#{bill.id}"
      last_modified = response.headers["Last-Modified"]

      travel_to(1.hour.from_now) do
        bill_score.update_columns(for: 50, updated_at: Time.current)
        expect(bill.reload.updated_at).to eq(original_bill_updated_at)

        get "/embed/bills/#{bill.id}", headers: {"If-Modified-Since" => last_modified}
        expect(response).to have_http_status(:ok)
        expect(inertia.props[:bill][:pro_count]).to eq(50)
      end
    end

    it "returns 404 Not Found for nonexistent bill" do
      get "/embed/bills/999999999"

      expect(response).to have_http_status(:not_found)
    end
  end
end
