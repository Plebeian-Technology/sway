# frozen_string_literal: true

# @lat: [[on-user-email-saved-send-email-job-design#Why only two exception classes are retried]]
require "net/smtp"

class OnUserEmailSavedSendEmailToLegislatorJob < ApplicationJob
  queue_as :background

  # @lat: [[on-user-email-saved-send-email-job-design#Why the sending-state transition uses update!, not update]]
  retry_on Net::OpenTimeout,
    Net::SMTPServerBusy,
    wait: :polynomially_longer,
    attempts: 3

  def perform(user_legislator_email)
    return unless user_legislator_email.sendable?

    if user_legislator_email.persisted?
      claimed = UserLegislatorEmail
        .where(id: user_legislator_email.id, status: %w[pending failed])
        .update_all(status: UserLegislatorEmail.statuses["sending"], updated_at: Time.current)
      return unless claimed == 1
    end

    # @lat: [[on-user-email-saved-send-email-job-design#Why the sending-state transition uses update!, not update]]
    user_legislator_email.update!(
      status: UserLegislatorEmail.statuses["sending"]
    )
    user_legislator_email.send_email
  rescue
    # @lat: [[on-user-email-saved-send-email-job-design#Why only two exception classes are retried]]
    if user_legislator_email.persisted?
      user_legislator_email.update_columns(
        status: UserLegislatorEmail.statuses["failed"],
        updated_at: Time.current
      )
    else
      user_legislator_email.update(
        status: UserLegislatorEmail.statuses["failed"]
      )
    end
    raise
  end
end
