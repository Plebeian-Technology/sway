require 'rails_helper'

RSpec.describe "Invites", type: :request do
  describe "GET /show" do
    it "returns http success" do
      get "/invites/show"
      expect(response).to have_http_status(301)
    end
  end

end
