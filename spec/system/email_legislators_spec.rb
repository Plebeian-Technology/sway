# frozen_string_literal: true

require "rails_helper"

# @lat: [[bills-controller-design#The email-your-legislators modal has browser coverage]]
RSpec.describe "Email your legislators", type: :system, js: true do
  include_context "TwilioDouble"

  let(:sway_locale) { create(:sway_locale) }
  let(:district) { create(:district, sway_locale: sway_locale) }
  let(:legislator) do
    create(:legislator, district: district).tap do |l|
      l.update!(email: "rep@example.com")
      create(:legislator_term, legislator: l, district: district, title: "Rep.")
    end
  end
  let(:bill) { create(:bill, sway_locale: sway_locale, legislator: legislator) }

  def build_voter(email: nil, is_email_verified: false)
    user = create(:user)
    # @lat: [[bills-controller-design#The email-your-legislators modal has browser coverage]]
    user.update!(
      email: email,
      is_email_verified: is_email_verified
    )
    create(:user_legislator, user: user, legislator: legislator, active: true)
    user.complete!
    create(:user_vote, user: user, bill: bill)
    user
  end

  it "sends from a verified email: preview placeholder, name capture, send, and the status list" do
    user = build_voter(email: "voter@example.com", is_email_verified: true)

    sign_in_as(user)
    visit "/bills/#{bill.id}"
    wait_until_loaded

    find("[data-testid='btn-email-legislators']", wait: 10).click

    # Verified email goes straight to the send step.
    expect(page).to have_text("Message Your Legislators", wait: 10)
    within "[data-testid='email-send-step']" do
      # @lat: [[bills-controller-design#The email-your-legislators modal has browser coverage]]
      expect(page).to have_css("[data-testid='email-preview']", text: "{YOUR NAME}")
      fill_in "ulem-full-name", with: "Test Voter"
      click_button "Send"
    end

    expect(page).to have_text(
      "Sending emails to your representatives. You will be CC'ed on them.", wait: 10
    )
    row = UserLegislatorEmail.find_by(bill_id: bill.id)
    expect(row).to be_present
    expect(row.status).to eq("pending")
    expect(user.reload.full_name).to eq("Test Voter")

    # Reopening the modal lands on its first step, which lists one send status
    # per legislator.
    find("[data-testid='btn-email-legislators']").click
    statuses = find("[data-testid='legislator-email-statuses']", wait: 10)
    expect(statuses).to have_text("#{legislator.first_name} #{legislator.last_name}")
    expect(statuses).to have_text("pending")
  end

  it "verifies an unverified email through the Twilio email-channel code step" do
    user = build_voter

    sign_in_as(user)
    visit "/bills/#{bill.id}"
    wait_until_loaded

    find("[data-testid='btn-email-legislators']", wait: 10).click

    expect(page).to have_text("What's Your Email?", wait: 10)
    within "[data-testid='email-entry-step']" do
      fill_in "ulem-email", with: "fresh@example.com"
      click_button "Submit"
    end

    # TwilioDouble stands in for Twilio and approves the emailed code.
    expect(page).to have_text("Verify Your Email", wait: 10)
    within "[data-testid='email-code-step']" do
      fill_in "ulem-code", with: "123456"
      click_button "Verify"
    end

    # Submitting redirects and reloads, which refreshes the user prop, and the
    # modal moves on to the send step.
    expect(page).to have_text("Message Your Legislators", wait: 10)
    expect(page).to have_css("[data-testid='email-send-step']")
    expect(user.reload.is_email_verified).to be(true)
    expect(user.email).to eq("fresh@example.com")
  end
end
