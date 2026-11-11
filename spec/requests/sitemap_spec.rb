require "rails_helper"

RSpec.describe "Sitemaps", type: :request do
  describe "GET /sitemap.xml" do
    let(:sway_locale) { create(:sway_locale) }
    let(:district) { create(:district, sway_locale: sway_locale) }
    let(:legislator) { create(:legislator, district: district) }
    let(:bill) do
      create(:bill, legislator: legislator, sway_locale: sway_locale)
    end

    before do
      create(:legislator_term, legislator: legislator, district: district)
    end

    it "returns an xml sitemap with expected URLs" do
      bill
      inactive_bill = create(:bill, legislator: legislator, sway_locale: sway_locale, active: false)
      former_legislator = create(:legislator, district: district)
      create(:legislator_term, :prior_term, legislator: former_legislator, district: district)

      get "/sitemap.xml"

      expect(response).to have_http_status(:ok)
      expect(response.content_type).to include("application/xml")
      expect(response.body).to include(root_url)
      expect(response.body).to include(bills_url)
      expect(response.body).to include(legislators_url)
      expect(response.body).to include(
        bill_url(bill, sway_locale_id: sway_locale.id)
      )
      expect(response.body).not_to include(
        bill_url(inactive_bill, sway_locale_id: sway_locale.id)
      )
      expect(response.body).to include(
        legislator_url(legislator, sway_locale_id: sway_locale.id)
      )
      expect(response.body).not_to include(
        legislator_url(former_legislator, sway_locale_id: sway_locale.id)
      )
      expect(response.body).to include(
        bill_of_the_month_index_url(sway_locale_id: sway_locale.id)
      )
      expect(response.body).not_to include("bill_of_the_week")
    end

    it "includes bill_of_the_month_index_url for declared locales and excludes it for undeclared locales" do
      declared_locale = create(:sway_locale, :baltimore)
      undeclared_locale = create(:sway_locale, city: "bethesda", state: "MD", country: "United States")

      get "/sitemap.xml"

      expect(response).to have_http_status(:ok)
      expect(response.body).to include(
        bill_of_the_month_index_url(sway_locale_id: declared_locale.id)
      )
      expect(response.body).not_to include(
        bill_of_the_month_index_url(sway_locale_id: undeclared_locale.id)
      )
    end

    # @lat: [[sitemap-forced-xml-format#Why GET /sitemap.xml forces the XML format]]
    it "renders the XML sitemap even when the request Accept header is HTML" do
      bill

      get "/sitemap.xml", headers: {"Accept" => "text/html"}

      expect(response).to have_http_status(:ok)
      expect(response.content_type).to include("application/xml")
      expect(response.body).to include(bills_url)
    end
  end
end
