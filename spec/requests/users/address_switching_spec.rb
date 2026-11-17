require "rails_helper"

RSpec.describe "/users/address", type: :request do
  include_context "SessionDouble"
  include_context "Setup"

  let(:user) { create(:user, :registered) }
  before { sign_in(user) }

  describe "GET /users/address/edit" do
    it "renders the AddressEdit component" do
      get "/users/address/edit"
      expect(inertia).to render_component "users/AddressEdit"
    end
  end
end
