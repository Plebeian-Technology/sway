# frozen_string_literal: true

require "rails_helper"

RSpec.describe "/influence", type: :request do
  include_context "SessionDouble"
  include_context "Setup"

  describe "GET /influence" do
    context "when user is signed in and registration is complete" do
      it "renders the Influence component" do
        _sway_locale, user = setup
        user.complete!

        get influence_index_path
        expect(inertia).to render_component Pages::INFLUENCE
      end

      it "passes the influence prop" do
        _sway_locale, user = setup
        user.complete!

        get influence_index_path
        expect(inertia).to have_props { |p|
          influence = p["influence"] || p[:influence]
          influence.is_a?(Hash) &&
            influence.key?("count_bills_shared") &&
            influence.key?("total_sway")
        }
      end

      it "accurately reflects redeemed bill share count and total sway in the influence prop" do
        sway_locale, user = setup
        user.complete!
        district = create(:district, sway_locale:)
        legislator = create(:legislator, district:)
        bill = create(:bill, legislator:, sway_locale:)
        create(:user_bill_share, :redeemed, user:, bill:)

        get influence_index_path
        expect(inertia).to have_props { |p|
          influence = p["influence"] || p[:influence]
          influence.is_a?(Hash) &&
            influence["count_bills_shared"] == 1 &&
            influence["total_sway"] >= 1
        }
      end
    end

    context "when user is not signed in" do
      it "falls back to root path with a sign-in flash notice when no referer is present" do
        get influence_index_path
        expect(response).to redirect_to(root_path)
        expect(flash[:notice]).to eq("Sign up or sign in to view this page.")
      end

      it "redirects back to the referer with a sign-in flash notice" do
        get influence_index_path, headers: {"HTTP_REFERER" => "http://www.example.com/bills"}
        expect(response).to redirect_to("http://www.example.com/bills")
        expect(flash[:notice]).to eq("Sign up or sign in to view this page.")
      end
    end

    context "when user registration is incomplete" do
      it "redirects to registration path with a sign-in flash notice" do
        _sway_locale, _user = setup_pre_registration

        get influence_index_path
        expect(response).to redirect_to(sway_registration_index_path)
        expect(flash[:notice]).to eq("Sign up or sign in to view this page.")
      end
    end
  end
end
