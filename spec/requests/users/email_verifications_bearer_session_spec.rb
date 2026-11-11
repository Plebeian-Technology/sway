# frozen_string_literal: true

require "rails_helper"

# @lat: [[email-verifications-controller-notes#Why the pending address lives only in the session]]
RSpec.describe "Users::EmailVerifications with a bearer client and a real session cookie", type: :request do
  # @type self: EmailVerificationsBearerSessionRequestSpecContext
  include_context "TwilioDouble"
  include_context "Setup"

  around do |example|
    with_app_config(:dev_login, skip_phone_verification: false) { example.run }
  end

  around do |example|
    original = ActionController::Base.allow_forgery_protection
    ActionController::Base.allow_forgery_protection = true
    example.run
  ensure
    ActionController::Base.allow_forgery_protection = original
  end

  let!(:sway_and_user) { setup }
  let(:sway_locale) { sway_and_user.first }
  let(:user) { sway_and_user.last }
  let(:bill) { create(:bill, sway_locale:) }
  let(:headers) { authenticate_as(user).merge("Accept" => "application/json") }
  let(:session_cookie_name) { Rails.application.config.session_options.fetch(:key) }
  let(:start_over_message) { "Start over and re-enter your email address." }

  # @lat: [[steep-typed-spec-helpers#let and def inside a describe block#Accepting the gap with steep:ignore instead of moving the helper out]]
  # steep:ignore:start
  def request_code
    post "/users/email_verification",
      params: {email_verification: {email: "voter@example.com", bill_id: bill.id}},
      headers:,
      as: :json
  end

  def check_code
    patch "/users/email_verification",
      params: {email_verification: {code: "123456", bill_id: bill.id}},
      headers:,
      as: :json
  end

  def expect_start_over_failure
    expect(response).to have_http_status(:unprocessable_content)
    expect(json_body[:error][:code]).to eq("email_verification_failed")
    expect(json_body[:error][:details][:code]).to eq(start_over_message)
    expect(twilio_verification_checks_double).not_to have_received(:create)
    expect(user.reload.is_email_verified).to be(false)
  end
  # steep:ignore:end

  describe "POST /users/email_verification" do
    it "answers a bearer request with success and sets a session cookie" do
      request_code

      expect(response).to have_http_status(:ok)
      expect(json_body[:flash]).to eq("Confirmation code sent! Check your email.")
      expect(response.cookies[session_cookie_name]).to be_present
      expect(twilio_verifications_double).to have_received(:create)
        .with(to: "voter@example.com", channel: "email")
      expect(user.reload.email).to be_nil
    end
  end

  describe "PATCH /users/email_verification" do
    it "verifies the address when the session cookie from #create is replayed" do
      request_code
      expect(cookies[session_cookie_name]).to be_present

      check_code

      expect(response).to have_http_status(:ok)
      expect(json_body[:flash]).to eq("Email verified!")
      user.reload
      expect(user.email).to eq("voter@example.com")
      expect(user.is_email_verified).to be(true)
      expect(twilio_verification_checks_double).to have_received(:create)
        .with(to: "voter@example.com", code: "123456")
    end

    it "answers with the start-over failure when the session cookie is dropped between #create and #update" do
      request_code
      expect(cookies[session_cookie_name]).to be_present
      cookies.delete(session_cookie_name)
      expect(cookies[session_cookie_name]).to be_blank

      check_code

      expect_start_over_failure
    end

    it "answers with the start-over failure when #update runs with no prior #create" do
      check_code

      expect_start_over_failure
    end
  end
end
