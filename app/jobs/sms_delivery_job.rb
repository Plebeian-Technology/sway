# frozen_string_literal: true

class SmsDeliveryJob < ApplicationJob
  queue_as :default

  # @lat: [[twilio-error-phone-redaction#Why SmsDeliveryJob raises DeliveryError outside the rescue block]]
  class DeliveryError < StandardError; end

  retry_on DeliveryError, wait: :polynomially_longer, attempts: 3

  # @lat: [[sms-notification-service-design#Why the opt-out suffix is appended once in SmsDeliveryJob]]
  OPT_OUT_SUFFIX = "Reply STOP to opt out."

  def perform(to:, body:)
    return unless to.present? && body.present?

    # @lat: [[seeded-development-users#Outbound SMS is refused outside production]]
    unless Rails.env.production? || Sway::Settings.ops.allow_nonproduction_sms
      SwayLogging.info("SmsDeliveryJob - refused: outbound SMS is production-only")
      return
    end

    # @lat: [[twilio-error-phone-redaction#Why the TWILIO_FROM_PHONE blank check has a known gap]]
    from = EnvSecret.read("TWILIO_FROM_PHONE")
    if from.blank?
      SwayLogging.warn("SmsDeliveryJob - TWILIO_FROM_PHONE is not set")
      return
    end

    client = Sway::TwilioClient.build
    body = append_opt_out_suffix(body)

    error_info = nil
    begin
      client.messages.create(from: from, to: to, body: body)
    rescue Twilio::REST::RestError => e
      # @lat: [[twilio-error-phone-redaction#Why SmsDeliveryJob raises DeliveryError outside the rescue block]]
      error_info = "code=#{e.code}, status=#{e.status_code}"
    end

    return if error_info.nil?

    SwayLogging.warn("SmsDeliveryJob - Twilio delivery failed (#{error_info})")
    # @lat: [[twilio-error-phone-redaction#Why SmsDeliveryJob raises DeliveryError outside the rescue block]]
    raise DeliveryError, "Twilio SMS delivery failed (#{error_info})"
  end

  private

  # @lat: [[sms-notification-service-design#Why the opt-out suffix is appended once in SmsDeliveryJob]]
  def append_opt_out_suffix(body)
    return body if body.end_with?(OPT_OUT_SUFFIX)

    "#{body} #{OPT_OUT_SUFFIX}"
  end
end
