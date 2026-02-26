require "rails_helper"

RSpec.describe "UserEmailConfirmations", type: :request do
  describe "GET /user_email_confirmation" do
    it "redirects to sway.vote via fallback route" do
      get "/user_email_confirmation"

      expect(response).to have_http_status(:redirect)
      expect(response).to redirect_to("https://sway.vote")
    end
  end
end
