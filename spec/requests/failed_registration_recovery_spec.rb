# frozen_string_literal: true

require "rails_helper"

# @lat: [[identity-and-access#Registration is asynchronous by necessity]]
RSpec.describe "failed-registration recovery", type: :request do
  include_context "SessionDouble"
  include_context "Setup"

  it "self-heals an incomplete user with legislators on the next request instead of 500ing" do
    # setup signs the user in and links a UserLegislator.
    _sway_locale, user = setup
    user.update_columns(registration_status: "pending", is_registration_complete: false)

    get notifications_path

    expect(response).not_to have_http_status(:internal_server_error)
    user.reload
    expect(user.registration_status).to eq("completed")
    expect(user.is_registration_complete).to be(true)
  end
end
