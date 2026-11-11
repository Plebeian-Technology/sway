# frozen_string_literal: true

require "rails_helper"

# @lat: [[twilio-inbound-opt-out-webhook#Why the spec computes a real signature instead of stubbing the validator]]
RSpec.describe "Webhooks::TwilioMessages", type: :request do
  let(:auth_token) { "test-webhook-token" }
  let(:webhook_path) { "/webhooks/twilio/sms" }
  let(:webhook_url) { "http://www.example.com#{webhook_path}" }

  # @lat: [[twilio-inbound-opt-out-webhook#Why the spec computes a real signature instead of stubbing the validator]]
  def signature_for(url, params, token)
    payload = +url.to_s
    params.sort.each { |key, value| payload << key.to_s << value.to_s }
    Base64.strict_encode64(OpenSSL::HMAC.digest("sha1", token, payload))
  end

  def post_sms(body:, from:, token: nil, signature: nil)
    token ||= auth_token
    params = {"Body" => body, "From" => from}
    sig = signature || signature_for(webhook_url, params, token)
    with_env("TWILIO_AUTH_TOKEN" => token) do
      post webhook_path, params: params, headers: {"X-Twilio-Signature" => sig}
    end
  end

  # @lat: [[inbound-sms#Inbound SMS#Twilio delivers each message to exactly one handler]]
  describe "forwarding ordinary correspondence" do
    include ActiveJob::TestHelper

    around do |example|
      original = ActiveJob::Base.queue_adapter
      ActiveJob::Base.queue_adapter = :test
      example.run
      ActiveJob::Base.queue_adapter = original
    end

    before { ActionMailer::Base.deliveries.clear }

    it "emails a real message through the webhook, end to end" do
      create(:user, phone: "4105551234")

      perform_enqueued_jobs do
        post_sms(body: "When is the next bill posted?", from: "+14105551234")
      end

      expect(response).to have_http_status(:no_content)
      mail = ActionMailer::Base.deliveries.last
      expect(mail.to).to eq([Sway::Settings.ops.inbound_sms_forward_to])
      expect((mail.text_part || mail).body.to_s).to include("When is the next bill posted?")
    end

    it "sends no email when the message is a STOP keyword" do
      create(:user, phone: "4105551234")

      expect {
        perform_enqueued_jobs { post_sms(body: "STOP", from: "+14105551234") }
      }.not_to change { ActionMailer::Base.deliveries.size }
    end
  end

  describe "POST /webhooks/twilio/sms" do
    it "flips sms_notifications_enabled to false on a valid-signature STOP" do
      user = create(:user, phone: "4105551234")
      user.update_column(:sms_notifications_enabled, true)

      post_sms(body: "STOP", from: "+14105551234")

      expect(response).to have_http_status(:no_content)
      expect(user.reload.sms_notifications_enabled).to be(false)
    end

    it "flips sms_notifications_enabled to true on a valid-signature START" do
      user = create(:user, phone: "4105551234")

      post_sms(body: "START", from: "+14105551234")

      expect(response).to have_http_status(:no_content)
      expect(user.reload.sms_notifications_enabled).to be(true)
    end

    %w[STOP STOPALL UNSUBSCRIBE CANCEL END QUIT OPTOUT REVOKE].each do |keyword|
      it "treats #{keyword} as an opt-out keyword" do
        user = create(:user, phone: "4105551234")
        user.update_column(:sms_notifications_enabled, true)

        post_sms(body: keyword, from: "+14105551234")

        expect(response).to have_http_status(:no_content)
        expect(user.reload.sms_notifications_enabled).to be(false)
      end
    end

    %w[START YES UNSTOP].each do |keyword|
      it "treats #{keyword} as an opt-in keyword" do
        user = create(:user, phone: "4105551234")

        post_sms(body: keyword, from: "+14105551234")

        expect(response).to have_http_status(:no_content)
        expect(user.reload.sms_notifications_enabled).to be(true)
      end
    end

    it "matches case-insensitively and ignores surrounding whitespace" do
      user = create(:user, phone: "4105551234")
      user.update_column(:sms_notifications_enabled, true)

      post_sms(body: " stop ", from: "+14105551234")

      expect(response).to have_http_status(:no_content)
      expect(user.reload.sms_notifications_enabled).to be(false)
    end

    it "leaves the flag untouched for an unrelated body" do
      user = create(:user, phone: "4105551234")
      user.update_column(:sms_notifications_enabled, true)

      post_sms(body: "hello", from: "+14105551234")

      expect(response).to have_http_status(:no_content)
      expect(user.reload.sms_notifications_enabled).to be(true)
    end

    it "rejects an invalid signature with 403 and leaves the flag unchanged" do
      user = create(:user, phone: "4105551234")
      user.update_column(:sms_notifications_enabled, true)

      post_sms(body: "STOP", from: "+14105551234", signature: "not-a-real-signature")

      expect(response).to have_http_status(:forbidden)
      expect(user.reload.sms_notifications_enabled).to be(true)
    end

    it "rejects a request missing the X-Twilio-Signature header entirely" do
      user = create(:user, phone: "4105551234")
      user.update_column(:sms_notifications_enabled, true)

      with_env("TWILIO_AUTH_TOKEN" => auth_token) do
        post webhook_path, params: {"Body" => "STOP", "From" => "+14105551234"}
      end

      expect(response).to have_http_status(:forbidden)
      expect(user.reload.sms_notifications_enabled).to be(true)
    end

    it "does not silently succeed when TWILIO_AUTH_TOKEN is blank" do
      user = create(:user, phone: "4105551234")
      user.update_column(:sms_notifications_enabled, true)
      params = {"Body" => "STOP", "From" => "+14105551234"}
      sig = signature_for(webhook_url, params, "some-token-that-is-not-configured")

      with_env("TWILIO_AUTH_TOKEN" => nil) do
        post webhook_path, params: params, headers: {"X-Twilio-Signature" => sig}
      end

      expect(response).to have_http_status(:service_unavailable)
      expect(user.reload.sms_notifications_enabled).to be(true)
    end

    it "resolves an E.164 From to the user whose stored phone is the normalized 10-digit form" do
      user = create(:user, phone: "2025551234")
      user.update_column(:sms_notifications_enabled, true)

      post_sms(body: "STOP", from: "+12025551234")

      expect(response).to have_http_status(:no_content)
      expect(user.reload.sms_notifications_enabled).to be(false)
    end

    # @lat: [[twilio-inbound-opt-out-webhook#Why an unknown phone number returns success, not an error]]
    it "returns 204 for an unknown phone number without raising" do
      expect {
        post_sms(body: "STOP", from: "+19995551234")
      }.not_to raise_error

      expect(response).to have_http_status(:no_content)
    end

    # @lat: [[twilio-inbound-opt-out-webhook#Why the response carries no TwiML body]]
    it "answers with no body at all, so Twilio sends no second reply" do
      create(:user, phone: "4105551234")

      post_sms(body: "STOP", from: "+14105551234")

      expect(response).to have_http_status(:no_content)
      expect(response.body).to be_empty
    end

    it "requires no sign-in or session at all" do
      user = create(:user, phone: "4105551234")
      user.update_column(:sms_notifications_enabled, true)

      post_sms(body: "STOP", from: "+14105551234")

      expect(response).not_to have_http_status(:unauthorized)
      expect(response).to have_http_status(:no_content)
    end
  end
end
