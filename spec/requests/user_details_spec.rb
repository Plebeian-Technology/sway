require "rails_helper"

RSpec.describe "UserDetails", type: :request do
  include_context "SessionDouble"
  include_context "Setup"

  describe "POST /user_details", inertia: true do
    it "updates a user's full name" do
      _sway_locale, user = setup

      post users_details_path, params: {
        user_detail: {
          bill_id: 1,
          user_id: user.id,
          full_name: "Taco Banana"
        }
      }

      expect(response).to have_http_status(302)
      expect(User.find(user.id).full_name).to eql("Taco Banana")
    end

    it "does not update a user's full name" do
      _sway_locale, user = setup

      post users_details_path, params: {
        user_detail: {
          bill_id: 1,
          user_id: user.id,
          full_name: "<scripat></script>"
        }
      }

      expect(response).to have_http_status(302)
      expect(User.find(user.id).full_name).to_not eql("<scripat></script>")
    end
  end
end
