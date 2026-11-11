# frozen_string_literal: true

module Webhooks
  # @lat: [[twilio-inbound-opt-out-webhook#Why the spec computes a real signature instead of stubbing the validator]]
  class TwilioMessagesController < ApplicationController
    skip_before_action :authenticate_sway_user!
    skip_before_action :verify_authenticity_token
    skip_before_action :is_api_request_and_is_route_api_accessible?

    def create
      auth_token = EnvSecret.read("TWILIO_AUTH_TOKEN")
      if auth_token.nil?
        SwayLogging.warn("twilio_sms_webhook.auth_token_blank")
        return head :service_unavailable
      end

      unless valid_signature?(auth_token)
        SwayLogging.warn("twilio_sms_webhook.invalid_signature")
        return head :forbidden
      end

      SmsOptOutService.new(from: params[:From], body: params[:Body]).call
      # @lat: [[inbound-sms#Inbound SMS#Twilio delivers each message to exactly one handler]]
      InboundSmsForwardingService.new(from: params[:From], body: params[:Body]).call
      head :no_content
    end

    private

    # @lat: [[twilio-inbound-opt-out-webhook#The signature/URL proxy caveat — check this first if signatures start rejecting]]
    # @lat: [[twilio-inbound-opt-out-webhook#Why the spec computes a real signature instead of stubbing the validator]]
    def valid_signature?(auth_token)
      signature = request.headers["X-Twilio-Signature"]
      return false if signature.blank?

      validator = Twilio::Security::RequestValidator.new(auth_token)
      validator.validate(request.original_url, request.request_parameters, signature)
    end
  end
end
