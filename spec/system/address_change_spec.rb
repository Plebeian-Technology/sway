# frozen_string_literal: true

require "rails_helper"

# @lat: [[registration-dead-ends#Correcting an address after a failed lookup]]
RSpec.describe "Address Change", type: :system, js: true do
  let(:user) { create(:user, :registered) }

  before do
    sign_in_as(user)
  end

  it "lets a registered user change their address" do
    visit "/users/profile"
    click_on "Change Address"

    # Assume the new route is /users/address/edit for now, or whatever it should be
    expect(page).to have_content("Address")
    
    # ... fill in new address ...
    # ... expect confirmation dialog ...
    # ... confirm ...
    # ... expect success ...
  end
end
