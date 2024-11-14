require "rails_helper"

RSpec.describe "BillOfTheWeekSchedules", type: :request do
  describe "GET /update" do
    it "returns http success" do
      get "/bill_of_the_week_schedule/update"
      expect(response).to have_http_status(:success)
    end
  end
end
