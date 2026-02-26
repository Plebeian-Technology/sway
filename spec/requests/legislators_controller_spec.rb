require "rails_helper"

RSpec.describe "LegislatorsController", type: :request do
  include_context "SessionDouble"
  include_context "Setup"

  describe "GET /index" do
    it "gets legislators for a user in a sway locale" do
      sway_locale, user = setup
      legislator = sway_locale.legislators.first # only 1 legislator has been created
      expect(legislator).to_not be_nil

      get "/legislators"

      expect(inertia).to render_component Pages::LEGISLATORS
      user_legislator = user.user_legislators.find_by(legislator:)
      expected_legislator_json =
        legislator.to_sway_json.merge(
          {
            user_legislator_score:
              user_legislator
                .user_legislator_score
                .to_builder
                .attributes!
                .except("is_a?"),
          },
        )
      expect(inertia).to have_props({ legislators: [expected_legislator_json] })
    end
  end
end
