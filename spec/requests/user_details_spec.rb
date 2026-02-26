require "rails_helper"

RSpec.describe "UserDetails", type: :request do
  include_context "SessionDouble"
  include_context "Setup"

  describe "POST /user_details" do
    it "updates a user's full name and redirects to bill path (legacy behavior)" do
      _sway_locale, user = setup
      bill_id = 1

      post users_details_path,
           params: {
             user_detail: {
               bill_id: bill_id,
               user_id: user.id,
               full_name: "Taco Banana",
             },
           }

      expect(response).to have_http_status(302)
      expect(response).to redirect_to(
        bill_path(bill_id, with: "legislator,address"),
      )
      expect(User.find(user.id).full_name).to eql("Taco Banana")
    end

    it "does not update a user's full name with invalid input" do
      _sway_locale, user = setup

      post users_details_path,
           params: {
             user_detail: {
               bill_id: 1,
               user_id: user.id,
               full_name: "<scripat></script>",
             },
           }

      expect(response).to have_http_status(302)
      expect(User.find(user.id).full_name).to_not eql("<scripat></script>")
    end

    it "redirects to redirect_url if provided" do
      _sway_locale, user = setup
      redirect_url = "/some/custom/path"

      post users_details_path,
           params: {
             user_detail: {
               user_id: user.id,
               full_name: "Redirect User",
               redirect_url: redirect_url,
             },
           }

      expect(response).to have_http_status(302)
      expect(response).to redirect_to(redirect_url)
      expect(User.find(user.id).full_name).to eql("Redirect User")
    end

    it "redirects to root path if neither bill_id nor redirect_url provided" do
      _sway_locale, user = setup

      post users_details_path,
           params: {
             user_detail: {
               user_id: user.id,
               full_name: "Root User",
             },
           }

      expect(response).to have_http_status(302)
      expect(response).to redirect_to(root_path)
      expect(User.find(user.id).full_name).to eql("Root User")
    end
  end
end
