require 'rails_helper'

RSpec.describe "OrganizationBillPositions", type: :request do
  describe "GET /index" do
    it "returns http success" do
      get "/organization_bill_positions/index"
      expect(response).to have_http_status(301)
    end
  end

  describe "GET /show" do
    it "returns http success" do
      get "/organization_bill_positions/show"
      expect(response).to have_http_status(301)
    end
  end

  describe "GET /create" do
    it "returns http success" do
      get "/organization_bill_positions/create"
      expect(response).to have_http_status(301)
    end
  end

end
