require "rails_helper"

# @lat: [[catch-all-enabled-production-only#spec/requests/user_email_confirmation_spec.rb records a route that does not exist]]
RSpec.describe "UserEmailConfirmations", type: :request do
  describe "GET /user_email_confirmation" do
    it "is not a route this app serves" do
      get "/user_email_confirmation"

      expect(response).to have_http_status(:not_found)
    end
  end
end
