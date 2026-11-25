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
      expect(inertia.props[:bill]).to include(pro_percent: 85, con_percent: 15)
      expect(inertia.props[:cta_url]).to eq("/bills/#{bill.id}")
    end

    # @lat: [[voter-privacy-threshold#The embed widget withholds counts on the server]]
    it "withholds the percentages while the bill has nine votes" do
      bill_score.update!(for: 6, against: 3)

      get "/embed/bills/#{bill.id}"

      expect(inertia.props[:bill]).to include(pro_percent: nil, con_percent: nil, comparison_suppressed: true)
    end

    it "sends the percentages and the flag once the bill has ten votes" do
      bill_score.update!(for: 7, against: 3)

      get "/embed/bills/#{bill.id}"

      expect(inertia.props[:bill]).to include(pro_percent: 70, con_percent: 30, comparison_suppressed: false)
    end

    # @lat: [[voter-privacy-threshold#No endpoint sends a count that could identify a voter]]
    it "sends no vote count, voter total or voters-needed number for a bill with thirty voters" do
      get "/embed/bills/#{bill.id}"

      expect(inertia.props[:bill].keys).not_to include(:pro_count, :con_count, :total_votes, :voters_needed)
      expect(response.body).not_to match(/pro_count|con_count|total_votes|voters_needed/)
    end

    it "carries payload version 4 in its cache tag" do
      expect(Embed::BillsController::PAYLOAD_VERSION).to eq("4")
    end

    # @lat: [[voter-privacy-threshold#The embed widget withholds counts on the server]]
    {
      "nineteen votes, thirteen For" => [13, 6, 70, 30],
      "forty votes, thirty-nine For" => [39, 1, 95, 5]
    }.each do |description, (pro, con, pro_percent, con_percent)|
      it "sends #{pro_percent} and #{con_percent} for #{description}" do
        bill_score.update!(for: pro, against: con)

        get "/embed/bills/#{bill.id}"

        expect(inertia.props[:bill]).to include(pro_percent:, con_percent:, comparison_suppressed: false)
      end
    end

    # @lat: [[voter-privacy-threshold#The embed widget withholds counts on the server]]
    it "withholds a unanimous split of ten votes like one under ten" do
      bill_score.update!(for: 10, against: 0)

      get "/embed/bills/#{bill.id}"

      expect(inertia.props[:bill]).to include(pro_percent: nil, con_percent: nil, comparison_suppressed: true)
    end

    it "answers a conditional GET holding the previous payload version's ETag with a full body" do
      current_version = Embed::BillsController::PAYLOAD_VERSION
      stub_const("Embed::BillsController::PAYLOAD_VERSION", "2")
      get "/embed/bills/#{bill.id}"
      old_etag = response.headers["ETag"]

      stub_const("Embed::BillsController::PAYLOAD_VERSION", current_version)
      get "/embed/bills/#{bill.id}", headers: {"If-None-Match" => old_etag}

      expect(response).to have_http_status(:ok)
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
      expect(inertia.props[:bill]).to include(pro_percent: nil, con_percent: nil, comparison_suppressed: true)
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

      original_bill_updated_at = bill.updated_at
      travel_to(1.hour.from_now) do
        bill_score.update_columns(for: 100, against: 20, updated_at: Time.current)
        expect(bill.reload.updated_at).to eq(original_bill_updated_at)

        get "/embed/bills/#{bill.id}", headers: {"If-None-Match" => original_etag}

        expect(response).to have_http_status(:ok)
        expect(response.headers["ETag"]).not_to eq(original_etag)
        expect(inertia.props[:bill]).to include(pro_percent: 85, con_percent: 15)
      end
    end

    # @lat: [[voter-privacy-threshold#The embed widget withholds counts on the server]]
    it "answers an If-Modified-Since-only conditional GET after a payload version change with a full body" do
      bill_score.update!(for: 6, against: 3)
      stub_const("Embed::BillsController::PAYLOAD_VERSION", "before")
      get "/embed/bills/#{bill.id}"
      expect(response).to have_http_status(:ok)

      stub_const("Embed::BillsController::PAYLOAD_VERSION", "after")
      get "/embed/bills/#{bill.id}", headers: {"If-Modified-Since" => 1.hour.from_now.httpdate}

      expect(response).to have_http_status(:ok)
      expect(inertia.props[:bill]).to include(pro_percent: nil, con_percent: nil, comparison_suppressed: true)
    end

    it "sends no Last-Modified header, so only the ETag can answer 304" do
      get "/embed/bills/#{bill.id}"

      expect(response.headers["ETag"]).to be_present
      expect(response.headers["Last-Modified"]).to be_nil
    end

    it "returns 404 Not Found for nonexistent bill" do
      get "/embed/bills/999999999"

      expect(response).to have_http_status(:not_found)
    end
  end
end
