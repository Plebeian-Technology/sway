# frozen_string_literal: true

# @lat: [[inbound-sms#Inbound SMS#Forwarding goes to email, not SMS]]
class InboundSmsMailer < ApplicationMailer
  def forward(from:, body:, known_sender:)
    @from = from
    @body = body
    @known_sender = known_sender

    origin = known_sender ? "known user" : "unknown sender"

    mail(
      to: Sway::Settings.ops.inbound_sms_forward_to,
      subject: "[Sway SMS] #{from} (#{origin})"
    )
  end
end
