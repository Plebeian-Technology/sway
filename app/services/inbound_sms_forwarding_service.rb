# frozen_string_literal: true

# @lat: [[inbound-sms#Inbound SMS]]
class InboundSmsForwardingService
  LINK_PATTERN = %r{https?://\S+|\b[a-z0-9-]+(\.[a-z0-9-]+)*\.[a-z]{2,}(/\S*)?}i

  def initialize(from:, body:)
    @from = from.to_s.strip
    @body = body.to_s.strip
  end

  def call
    return if @from.blank? || @body.blank?
    return if SmsKeywords.keyword?(@body)

    sender = User.find_by(phone: @from.normalize_phone)

    # @lat: [[inbound-sms#Inbound SMS#The spam rule is a link from a stranger]]
    return if sender.nil? && @body.match?(LINK_PATTERN)

    InboundSmsMailer.forward(from: @from, body: @body, known_sender: sender.present?)
      .deliver_later
  end
end
