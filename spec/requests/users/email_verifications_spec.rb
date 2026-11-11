# frozen_string_literal: true

require "rails_helper"

# @lat: [[email-verifications-controller-notes#Twilio error handling]]
RSpec.describe "Users::EmailVerifications", type: :request do
  include_context "SessionDouble"
  include_context "TwilioDouble"
  include_context "Setup"

  # The skip switch has to be off so the Twilio code actually runs. The
  # TwilioDouble catches every call, so nothing leaves the machine.
  around do |example|
    with_app_config(:dev_login, skip_phone_verification: false) { example.run }
  end

  describe "POST /users/email_verification" do
    it "sends an email-channel code and holds the address in session — never on the user row" do
      sway_locale, user = setup
      bill = create(:bill, sway_locale:)

      post "/users/email_verification",
        params: {email_verification: {email: "Voter@Example.com", bill_id: bill.id}}

      expect(response).to redirect_to(bill_path(bill.id, {with: "legislator,address"}))
      expect(session_hash[:pending_email]).to eq("voter@example.com")
      # Better than the deleted controller, which wrote user.email before the
      # address was verified, so a typo stuck to the account.
      expect(user.reload.email).to be_nil
      expect(twilio_verifications_double).to have_received(:create)
        .with(to: "voter@example.com", channel: "email")
    end

    it "rejects a malformed address without contacting Twilio" do
      sway_locale, _user = setup
      bill = create(:bill, sway_locale:)

      post "/users/email_verification",
        params: {email_verification: {email: "not-an-email", bill_id: bill.id}}

      expect(response).to have_http_status(:redirect)
      expect(session_hash[:pending_email]).to be_nil
      expect(twilio_verifications_double).not_to have_received(:create)
    end

    it "redirects unauthenticated callers to root" do
      post "/users/email_verification",
        params: {email_verification: {email: "voter@example.com"}}

      expect(response).to redirect_to(root_url)
    end
  end

  describe "PATCH /users/email_verification" do
    it "writes email + is_email_verified atomically on approval and clears the pending address" do
      sway_locale, user = setup
      bill = create(:bill, sway_locale:)
      session_hash[:pending_email] = "voter@example.com"

      patch "/users/email_verification",
        params: {email_verification: {code: "123456", bill_id: bill.id}}

      expect(response).to redirect_to(bill_path(bill.id, {with: "legislator,address"}))
      user.reload
      expect(user.email).to eq("voter@example.com")
      expect(user.is_email_verified).to be(true)
      expect(session_hash[:pending_email]).to be_nil
      expect(twilio_verification_checks_double).to have_received(:create)
        .with(to: "voter@example.com", code: "123456")
    end

    it "writes nothing when the code is not approved" do
      allow(twilio_verification_result).to receive(:status).and_return("pending")
      sway_locale, user = setup
      bill = create(:bill, sway_locale:)
      session_hash[:pending_email] = "voter@example.com"

      patch "/users/email_verification",
        params: {email_verification: {code: "999999", bill_id: bill.id}}

      expect(response).to have_http_status(:redirect)
      user.reload
      expect(user.email).to be_nil
      expect(user.is_email_verified).to be(false)
      expect(session_hash[:pending_email]).to eq("voter@example.com")
    end

    it "rejects a check with no pending address in session without contacting Twilio" do
      sway_locale, _user = setup
      bill = create(:bill, sway_locale:)

      patch "/users/email_verification",
        params: {email_verification: {code: "123456", bill_id: bill.id}}

      expect(response).to have_http_status(:redirect)
      expect(twilio_verification_checks_double).not_to have_received(:create)
    end

    it "surfaces an email-uniqueness collision as an Inertia error, not a 500" do
      sway_locale, user = setup
      create(:user, email: "taken@example.com")
      bill = create(:bill, sway_locale:)
      session_hash[:pending_email] = "taken@example.com"

      patch "/users/email_verification",
        params: {email_verification: {code: "123456", bill_id: bill.id}}

      expect(response).to have_http_status(:redirect)
      expect(user.reload.email).to be_nil
    end

    it "redirects with a friendly error when Twilio returns 20404 (expired check)" do
      twilio_error = Twilio::REST::RestError.allocate
      allow(twilio_error).to receive(:code).and_return(20_404)
      allow(twilio_error).to receive(:full_message).and_return("VerificationCheck was not found")
      allow(twilio_verification_checks_double).to receive(:create).and_raise(twilio_error)

      sway_locale, user = setup
      bill = create(:bill, sway_locale:)
      session_hash[:pending_email] = "voter@example.com"

      patch "/users/email_verification",
        params: {email_verification: {code: "123456", bill_id: bill.id}}

      expect(response).to have_http_status(:redirect)
      expect(user.reload.is_email_verified).to be(false)
    end

    # On an unexpected Twilio error the controller must stop with an error of
    # its own that carries no recipient address — not the raw RestError, whose
    # message includes it — and with no .cause holding personal data either.
    it "raises a sanitized error carrying no recipient email on unexpected Twilio errors" do
      twilio_error = Twilio::REST::RestError.allocate
      allow(twilio_error).to receive(:code).and_return(50_000)
      allow(twilio_error).to receive(:status_code).and_return(500)
      leaky = "The address voter@example.com is not a valid recipient."
      allow(twilio_error).to receive(:message).and_return(leaky)
      allow(twilio_error).to receive(:full_message).and_return(leaky)
      allow(twilio_verification_checks_double).to receive(:create).and_raise(twilio_error)

      sway_locale, _user = setup
      bill = create(:bill, sway_locale:)
      session_hash[:pending_email] = "voter@example.com"

      logged = [] #: Array[String]
      allow(Rails.logger).to receive(:warn) { |msg| logged << msg.to_s }

      raised = nil #: Authentication::TwilioVerificationError?
      expect do
        patch "/users/email_verification",
          params: {email_verification: {code: "123456", bill_id: bill.id}}
      end.to raise_error(Authentication::TwilioVerificationError) { |e| raised = e }

      expect(raised&.message.to_s).to include("code=50000")
      expect(raised&.message.to_s).not_to include("voter@example.com")
      expect(raised&.cause).to be_nil
      expect(logged.join("\n")).not_to include("voter@example.com")
    end

    it "clears session[:pending_email] after 5 failed guesses so a 6th attempt must start over without contacting Twilio" do
      allow(twilio_verification_result).to receive(:status).and_return("pending")
      sway_locale, user = setup
      bill = create(:bill, sway_locale:)
      session_hash[:pending_email] = "voter@example.com"
      session_hash[:pending_email_attempts] = 0

      5.times do |i|
        patch "/users/email_verification",
          params: {email_verification: {code: "00000#{i}", bill_id: bill.id}}
        expect(response).to have_http_status(:redirect)
      end

      expect(session_hash[:pending_email]).to be_nil
      expect(session_hash[:pending_email_attempts]).to be_nil
      expect(twilio_verification_checks_double).to have_received(:create).exactly(5).times

      allow(twilio_verification_result).to receive(:status).and_return("approved")
      patch "/users/email_verification",
        params: {email_verification: {code: "123456", bill_id: bill.id}}

      expect(response).to have_http_status(:redirect)
      expect(session_hash[:inertia_errors]).to eq({code: "Start over and re-enter your email address."})
      expect(twilio_verification_checks_double).to have_received(:create).exactly(5).times
      expect(user.reload.is_email_verified).to be(false)
    end

    it "rate-limits #update after 10 code check attempts within an hour" do
      with_rate_limit_enabled(:email_verify) do
        allow(twilio_verification_result).to receive(:status).and_return("pending")
        sway_locale, _user = setup
        bill = create(:bill, sway_locale:)

        11.times do
          session_hash[:pending_email] = "voter@example.com"
          patch "/users/email_verification",
            params: {email_verification: {code: "999999", bill_id: bill.id}},
            as: :json
        end

        expect(response).to have_http_status(:too_many_requests)
      end
    end
  end

  describe "DELETE /users/email_verification" do
    it "clears the pending address and resets a legacy-era unverified email" do
      sway_locale, user = setup
      user.update!(email: "old@example.com", is_email_verified: false)
      bill = create(:bill, sway_locale:)
      session_hash[:pending_email] = "new@example.com"
      session_hash[:pending_email_attempts] = 3

      # bill_id sits at the top level: DELETE bodies are not nested like POST bodies.
      delete "/users/email_verification", params: {bill_id: bill.id}

      expect(response).to redirect_to(bill_path(bill.id, {with: "legislator,address"}))
      expect(session_hash[:pending_email]).to be_nil
      expect(session_hash[:pending_email_attempts]).to be_nil
      user.reload
      expect(user.email).to be_nil
      expect(user.is_email_verified).to be(false)
    end

    it "leaves a verified email untouched" do
      sway_locale, user = setup
      user.update!(email: "verified@example.com", is_email_verified: true)
      bill = create(:bill, sway_locale:)

      delete "/users/email_verification", params: {bill_id: bill.id}

      user.reload
      expect(user.email).to eq("verified@example.com")
      expect(user.is_email_verified).to be(true)
    end
  end
end
