require "rails_helper"

RSpec.describe "BillScores", type: :request do
  include_context "SessionDouble"
  include_context "Setup"

  let(:user) { setup.last }
  let(:bill) { create(:bill) } # Creates a bill score

  before { sign_in user }

  describe "GET /bill_scores/:id" do
    context "when the bill score exists" do
      it "returns the bill score as JSON" do
        expect_any_instance_of(BillScore).to receive(
          :to_builder_with_user,
        ).with(user).and_call_original

        get bill_score_path(bill.id)
        expect(response).to have_http_status(:ok)
        json = JSON.parse(response.body)
        expect(json["id"]).to eq(bill.bill_score.id)
        expect(json["bill_id"]).to eq(bill.id)
      end
    end

    context "when the bill score does not exist" do
      it "returns nil JSON" do
        get bill_score_path(-1)
        expect(response).to have_http_status(:ok)
        expect(response.body).to eq("null")
      end
    end
  end
end
