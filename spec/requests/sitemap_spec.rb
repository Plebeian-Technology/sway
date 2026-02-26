require "rails_helper"

RSpec.describe "Sitemaps", type: :request do
  describe "GET /sitemap.xml" do
    let(:sway_locale) { create(:sway_locale) }
    let(:district) { create(:district, sway_locale: sway_locale) }
    let(:legislator) { create(:legislator, district: district) }
    let(:bill) { create(:bill, legislator: legislator, sway_locale: sway_locale) }

    it "returns an xml sitemap with expected URLs" do
      bill

      get "/sitemap.xml"

      expect(response).to have_http_status(:ok)
      expect(response.content_type).to include("application/xml")
      expect(response.body).to include(root_url)
      expect(response.body).to include(bills_url)
      expect(response.body).to include(legislators_url)
      expect(response.body).to include(bill_url(bill, sway_locale_id: sway_locale.id))
      expect(response.body).to include(
        legislator_url(legislator, sway_locale_id: sway_locale.id),
      )
    end
  end
end
