require 'rails_helper'

RSpec.describe "Notifications::PushNotifications", type: :request do
  describe "GET /create" do
    it "returns http success" do
      get "/notifications/push_notifications/create"
      expect(response).to have_http_status(:success)
    end
  end

end
