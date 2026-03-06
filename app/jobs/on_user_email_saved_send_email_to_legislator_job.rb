class OnUserEmailSavedSendEmailToLegislatorJob < ApplicationJob
  queue_as :background

  def perform(user_legislator_email)
    return unless user_legislator_email.sendable?
    user_legislator_email.update(
      status: UserLegislatorEmail.statuses["sending"],
    )
    user_legislator_email.send_email
  end
end
