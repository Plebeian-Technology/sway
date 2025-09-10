require "rails_helper"

RSpec.describe "LegislatorsController", type: :request, inertia: true do
    include_context "SessionDouble"
    include_context "Setup"

    describe "GET /index", inertia: true do
        it "gets legislators for a user in a sway locale" do
            sway_locale, _user = setup
            legislator = sway_locale.legislators.first # only 1 legislator has been created
            expect(legislator).to_not be_nil

            get "/legislators"

            expect(inertia).to render_component Pages::LEGISLATORS
            expect(inertia).to include_props({ legislators: [legislator.to_sway_json] })
        end
    end
end
