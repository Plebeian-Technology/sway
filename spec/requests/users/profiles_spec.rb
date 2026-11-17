# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Users::Profiles", type: :request do
  include_context "SessionDouble"
  include_context "Setup"

  describe "GET /users/profiles" do
    it "renders the profile page for a logged-in user" do
      _, user = setup
      get "/users/profile"
      expect(response).to have_http_status(:ok)
      expect(inertia).to render_component("users/Profile")
      # Need to check if user prop is passed
      expect(inertia.props[:user][:email]).to eq(user.email)
    end

    it "redirects to signin for an unauthenticated user" do
      get "/users/profile"
      expect(response).to have_http_status(:redirect)
      expect(response).to redirect_to("/")
    end
  end
end
