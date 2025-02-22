# typed: true

class OnUserEmailSavedSendEmailToLegislatorJob < ApplicationJob
  extend T::Sig

  queue_as :background

  sig { params(user_legislator_email: UserLegislatorEmail).void }
  def perform(user_legislator_email)
    if user_legislator_email.sendable?
      user_legislator_email.update(status: UserLegislatorEmail.statuses["sending"])
      user_legislator_email.send_email
    end
  end
end
