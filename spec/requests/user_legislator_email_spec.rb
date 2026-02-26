require "rails_helper"

RSpec.describe "UserLegislatorEmails", type: :request do
  include_context "SessionDouble"
  include_context "Setup"

  let(:setup_data) { setup }
  let(:sway_locale) { setup_data.first }
  let(:user) { setup_data.last }
  let(:bill) { create(:bill, sway_locale: sway_locale) }

  before { sign_in user }

  describe "POST /user_legislator_emails" do
    it "creates user legislator email records for the bill locale" do
      expect do
        post user_legislator_emails_path,
             params: {
               user_legislator_email: {
                 bill_id: bill.id,
               },
             }
      end.to change(UserLegislatorEmail, :count).by(1)

      expect(response).to redirect_to(bill_path(bill.id))
      expect(UserLegislatorEmail.last.bill).to eq(bill)
      expect(UserLegislatorEmail.last.user).to eq(user)
    end
  end
end
