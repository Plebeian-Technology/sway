# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Phone verification error sanitization", type: :system, js: true do
  include_context "TwilioDouble"

  around do |example|
    # The Twilio error only happens when the real phone check runs. The
    # server runs in a thread of this same process, so the swapped setting
    # is visible to it.
    with_app_config(:dev_login, skip_phone_verification: false) { example.run }
  end

  it "shows the sanitized not-found message without echoing the phone number" do
    # A plain local variable, not a `let`: the type checker cannot see helpers
    # defined with `let` from inside an example block (the same blind spot it
    # has for mupdf_extractor_spec's module constants).
    leaky_phone = "4105551212"
    expect(User.find_by(phone: leaky_phone)).to be_nil

    # Twilio raises an error whose message contains the phone number it was
    # texting — exactly the thing that used to leak onto the page.
    twilio_error = Twilio::REST::RestError.allocate
    allow(twilio_error).to receive_messages(
      code: 20_404,
      status_code: 404,
      message: "VerificationCheck was not found for recipient +1#{leaky_phone}",
      full_message: "VerificationCheck was not found for recipient +1#{leaky_phone}"
    )
    allow(twilio_verification_result).to receive(:status).and_raise(twilio_error)

    visit root_path
    expect(page).to have_button("Continue with Phone", disabled: false)
    expect(page).to have_no_css("#application-loading")
    fill_in "Phone number", with: leaky_phone
    click_button "Continue with Phone"

    # An unknown phone number goes down the SMS path to the code-entry step.
    expect(page).to have_field("v2-code", wait: 10)
    fill_in "v2-code", with: "000000"
    expect(page).to have_field("v2-code", with: "000000")
    expect(page).to have_button("Confirm code", disabled: false)
    click_button "Confirm code"

    # @lat: [[identity-and-access#Identity and access#The phone number is the account#A verification-not-found reply has one safe browser outcome]]
    # @lat: [[twilio-error-phone-redaction#Why Twilio error handling redacts recipient identifiers]]
    expect(page).to have_text("Code not found.", wait: 10)
    expect(page).to have_no_text("Incorrect Code")
    expect(page).to have_button("Confirm code")
    expect(page).to have_no_text(leaky_phone)
    expect(page).to have_no_text("+1#{leaky_phone}")
    expect(User.find_by(phone: leaky_phone)).to be_nil
  end
end
