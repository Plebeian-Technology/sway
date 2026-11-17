require "rails_helper"

RSpec.describe "/users/address", type: :request do
  include_context "SessionDouble"
  include_context "Setup"

  before do
    _sway_locale, user = setup
    sign_in(user)
  end

  describe "GET /users/address/edit" do
    it "renders the AddressEdit component" do
      get "/users/address/edit"
      expect(response).to have_http_status(:ok)
      expect(inertia).to render_component "users/AddressEdit"
    end
  end
end
