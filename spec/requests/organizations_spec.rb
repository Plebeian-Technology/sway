require 'rails_helper'

RSpec.describe "Organizations", type: :request do
  describe "GET /index" do
    it "returns http success" do
      get "/organizations/index"
      expect(response).to have_http_status(301)
    end
  end

  describe "GET /show" do
    it "returns http success" do
      get "/organizations/show"
      expect(response).to have_http_status(301)
    end
  end

  describe "GET /create" do
    it "returns http success" do
      get "/organizations/create"
      expect(response).to have_http_status(301)
    end
  end

end
