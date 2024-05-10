require 'rails_helper'

RSpec.describe "Invites", type: :request do
  describe "GET /index" do
    it "returns http success" do
      get "/invites/index"
      expect(response).to have_http_status(:success)
    end
  end

  describe "GET /show" do
    it "returns http success" do
      get "/invites/show"
      expect(response).to have_http_status(:success)
    end
  end

  describe "GET /create" do
    it "returns http success" do
      get "/invites/create"
      expect(response).to have_http_status(:success)
    end
  end

  describe "GET /destroy" do
    it "returns http success" do
      get "/invites/destroy"
      expect(response).to have_http_status(:success)
    end
  end

end
