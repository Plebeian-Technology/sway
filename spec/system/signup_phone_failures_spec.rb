# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Signup SMS step failure handling", type: :system, js: true do
  include ActiveSupport::Testing::TimeHelpers

  include_context "TwilioDouble"

  around do |example|
    with_app_config(:dev_login, skip_phone_verification: false) { example.run }
  end

  before do
    visit root_path
    expect(page).to have_button("Continue with Phone", disabled: false, wait: 10)
    expect(page).to have_no_css("#application-loading")
  end

  # @lat: [[signup-sms-failure-browser-tests#Signup SMS failure browser tests#Short phone number rejection]]
  it "shows a warning toast and stays on the phone step when the phone number has fewer than 10 digits" do
    fill_in "Phone number", with: "410555"
    click_button "Continue with Phone"

    expect(page).to have_text("Your phone number must be 10 digits.", wait: 10)
    expect(page).to have_no_field("v2-code")
    expect(page).to have_button("Continue with Phone", disabled: false)
    expect(User.find_by(phone: "410555")).to be_nil
  end

  # @lat: [[signup-sms-failure-browser-tests#Signup SMS failure browser tests#Empty confirmation code warning]]
  it "shows a warning toast and stays on the code step when the confirmation code is blank" do
    phone = "4105551212"
    fill_in "Phone number", with: phone
    click_button "Continue with Phone"

    expect(page).to have_field("v2-code", wait: 10)
    expect(page).to have_field("v2-code", with: "")
    click_button "Confirm code"

    expect(page).to have_text("Please enter your confirmation code.", wait: 10)
    expect(page).to have_field("v2-code")
    expect(page).to have_button("Confirm code", disabled: false)
    expect(User.find_by(phone: phone)).to be_nil
  end

  # @lat: [[signup-sms-failure-browser-tests#Signup SMS failure browser tests#Upstream error when sending code]]
  it "shows an error toast and remains on the phone step when Twilio refuses to send the code" do
    twilio_error = Twilio::REST::RestError.allocate
    allow(twilio_error).to receive_messages(
      code: 60_000,
      status_code: 400,
      message: "Unable to create record",
      full_message: "Unable to create record"
    )
    allow(twilio_verifications_double).to receive(:create).and_raise(twilio_error)

    phone = "4105551212"
    fill_in "Phone number", with: phone
    click_button "Continue with Phone"

    expect(page).to have_text("Could not send confirmation code. Please try again.", wait: 10)
    expect(page).to have_no_field("v2-code")
    expect(page).to have_button("Continue with Phone", disabled: false)
    expect(User.find_by(phone: phone)).to be_nil
  end

  # @lat: [[signup-sms-failure-browser-tests#Signup SMS failure browser tests#Upstream timeout when sending code]]
  it "shows an error toast and remains on the phone step when Twilio times out sending the code" do
    allow(twilio_verifications_double).to receive(:create).and_raise(
      Twilio::REST::TwilioError.new("timeout")
    )

    phone = "4105551212"
    fill_in "Phone number", with: phone
    click_button "Continue with Phone"

    expect(page).to have_text("Could not send confirmation code. Please try again.", wait: 10)
    expect(page).to have_no_field("v2-code")
    expect(page).to have_button("Continue with Phone", disabled: false)
    expect(User.find_by(phone: phone)).to be_nil
  end

  # @lat: [[signup-sms-failure-browser-tests#Signup SMS failure browser tests#Daily slot release after failed send]]
  it "releases the daily slot on a failed 10th send so retrying after cooldown succeeds" do
    with_rate_limit_enabled(:phone_verify) do
      twilio_error = Twilio::REST::RestError.allocate
      allow(twilio_error).to receive_messages(
        code: 60_000,
        status_code: 400,
        message: "Unable to create record",
        full_message: "Unable to create record"
      )

      first_attempt = true
      allow(twilio_verifications_double).to receive(:create) do
        if first_attempt
          first_attempt = false
          raise twilio_error
        end
        instance_double("TwilioVerification", sid: "VE123")
      end

      phone = "4105551212"
      begin
        9.times do
          PhoneVerificationSendLimit.claim(phone: phone, store: ApplicationController::RATE_LIMIT_STORE)
          travel 2.minutes
        end

        fill_in "Phone number", with: phone
        click_button "Continue with Phone"

        expect(page).to have_text("Could not send confirmation code. Please try again.", wait: 10)
        expect(page).to have_no_field("v2-code")
        expect(page).to have_button("Continue with Phone", disabled: false)

        travel 65.seconds
        click_button "Continue with Phone"

        expect(page).to have_field("v2-code", wait: 10)
        expect(page).to have_no_text("Too many")
        expect(User.find_by(phone: phone)).to be_nil
      ensure
        travel_back
      end
    end
  end

  # @lat: [[signup-sms-failure-browser-tests#Signup SMS failure browser tests#Incorrect confirmation code rejection]]
  it "shows an error toast and keeps the code step active when the entered code is incorrect" do
    allow(twilio_verification_result).to receive(:status).and_return("pending")

    phone = "4105551212"
    fill_in "Phone number", with: phone
    click_button "Continue with Phone"

    expect(page).to have_field("v2-code", wait: 10)
    fill_in "v2-code", with: "000000"
    click_button "Confirm code"

    expect(page).to have_text("Incorrect Code", wait: 10)
    expect(page).to have_field("v2-code")
    expect(page).to have_button("Confirm code", disabled: false)
    expect(User.find_by(phone: phone)).to be_nil
  end

  # @lat: [[signup-sms-failure-browser-tests#Signup SMS failure browser tests#Check attempt limit reached]]
  it "shows an error toast indicating the code is spent when Twilio check returns error 60202" do
    twilio_error = Twilio::REST::RestError.allocate
    allow(twilio_error).to receive_messages(
      code: 60_202,
      status_code: 400,
      message: "Max check attempts reached",
      full_message: "Max check attempts reached"
    )
    allow(twilio_verification_checks_double).to receive(:create).and_raise(twilio_error)

    phone = "4105551212"
    fill_in "Phone number", with: phone
    click_button "Continue with Phone"

    expect(page).to have_field("v2-code", wait: 10)
    fill_in "v2-code", with: "000000"
    click_button "Confirm code"

    expect(page).to have_text("This code can no longer be used. Please request a new code.", wait: 10)
    expect(page).to have_field("v2-code")
    expect(page).to have_button("Confirm code", disabled: false)
    expect(User.find_by(phone: phone)).to be_nil
  end

  # @lat: [[signup-sms-failure-browser-tests#Signup SMS failure browser tests#Upstream timeout when checking code]]
  it "shows an error toast and keeps the code step usable when Twilio times out checking the code" do
    allow(twilio_verification_checks_double).to receive(:create).and_raise(
      Twilio::REST::TwilioError.new("timeout")
    )

    phone = "4105551212"
    fill_in "Phone number", with: phone
    click_button "Continue with Phone"

    expect(page).to have_field("v2-code", wait: 10)
    fill_in "v2-code", with: "000000"
    click_button "Confirm code"

    expect(page).to have_text("Could not check the code. Please try again.", wait: 10)
    expect(page).to have_field("v2-code")
    expect(page).to have_button("Confirm code", disabled: false)
    expect(User.find_by(phone: phone)).to be_nil
  end

  # @lat: [[signup-sms-failure-browser-tests#Signup SMS failure browser tests#Second verification code request]]
  it "sends a second code for the same number when requesting again after cancel under rate limiting" do
    with_rate_limit_enabled(:phone_verify) do
      phone = "4105551212"
      fill_in "Phone number", with: phone
      click_button "Continue with Phone"

      expect(page).to have_field("v2-code", wait: 10)
      click_button "Cancel"

      expect(page).to have_no_field("v2-code")
      expect(page).to have_button("Continue with Phone", disabled: false)

      travel 65.seconds do
        click_button "Continue with Phone"

        expect(page).to have_field("v2-code", wait: 10)
        expect(page).to have_no_text("Too many")
        expect(twilio_verifications_double).to have_received(:create).twice
        expect(User.find_by(phone: phone)).to be_nil
      end
    end
  end

  # @lat: [[signup-sms-failure-browser-tests#Signup SMS failure browser tests#Cancel confirmation code entry]]
  it "returns to the phone form with the phone input enabled when cancel is clicked from the code step" do
    phone = "4105551212"
    fill_in "Phone number", with: phone
    click_button "Continue with Phone"

    expect(page).to have_field("v2-code", wait: 10)
    click_button "Cancel"

    expect(page).to have_field("Phone number", disabled: false)
    expect(page).to have_no_field("v2-code")
    expect(page).to have_button("Continue with Phone", disabled: false)
    expect(User.find_by(phone: phone)).to be_nil
  end
end
