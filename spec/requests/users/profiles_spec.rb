# frozen_string_literal: true

require "rails_helper"

RSpec.describe "GET /profile", type: :request do
  include_context "SessionDouble"
  include_context "Setup"

  it "renders the Profile page for a signed-in user" do
    setup

    get "/profile"

    expect(response).to have_http_status(:ok)
    expect(inertia).to render_component(Pages::PROFILE)
  end

  it "redirects a signed-out visitor the way other signed-in pages do" do
    get "/profile"

    expect(response).to redirect_to(root_url)
    expect(flash[:notice]).to eq("Sign up or sign in to view this page.")
  end

  it "tells an allowlisted user's page that it may link API keys" do
    _, user = setup
    stub_const("User::API_USER_PHONES", [user.phone].freeze)

    get "/profile"

    expect(inertia).to have_props(can_manage_api_keys: true)
  end

  it "tells any other user's page that it may not link API keys" do
    setup
    stub_const("User::API_USER_PHONES", [].freeze)

    get "/profile"

    expect(inertia).to have_props(can_manage_api_keys: false)
  end
end
