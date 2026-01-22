# frozen_string_literal: true
# typed: true

class SmsDeliveryJob < ApplicationJob
  queue_as :default

  def perform(to:, body:)
    return unless to.present? && body.present?

    from = ENV["TWILIO_FROM_PHONE"]
    if from.blank?
        Rails.logger.warn("SmsDeliveryJob - TWILIO_FROM_PHONE is not set")
        return
    end

    client = Twilio::REST::Client.new(
      ENV["TWILIO_ACCOUNT_SID"],
      ENV["TWILIO_AUTH_TOKEN"]
    )

    begin
      client.messages.create(
        from: from,
        to: to,
        body: body
      )
    rescue Twilio::REST::RestError => e
      Rails.logger.error("SmsDeliveryJob - Error sending SMS to #{to}: #{e.message}")
      # Optionally retry_job depending on error
    end
  end
end
