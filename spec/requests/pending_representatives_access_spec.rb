# frozen_string_literal: true

require "rails_helper"

RSpec.describe "A signed-in user waiting for representatives", type: :request do
  include_context "SessionDouble"

  let(:user) { create(:user) }
  let(:address) { create(:address) }

  before do
    UserAddress.create!(user:, address:)
    user.update_columns(registration_status: "completed", is_registration_complete: true)
    sign_in(user)
  end

  context "when a locale is pending and the user has no active legislator link" do
    before do
      congress = address.sway_locales.find(&:congress?)
      user.add_pending_representative_locale(congress)
    end

    it "opens the feed" do
      get feed_path

      expect(response).to have_http_status(:ok)
    end

    it "opens the legislators page" do
      get legislators_path

      expect(response).to have_http_status(:ok)
    end

    it "sends the registration page on to the feed" do
      get sway_registration_index_path

      expect(response).to redirect_to(feed_path)
    end
  end

  context "when no locale is pending and the user has no active legislator link" do
    it "sends the feed back to the registration page" do
      get feed_path

      expect(response).to redirect_to(sway_registration_index_path)
    end
  end
end
