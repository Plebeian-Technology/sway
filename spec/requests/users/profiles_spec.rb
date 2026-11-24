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
end
