# == Schema Information
#
# Table name: user_legislator_emails
# Database name: primary
#
#  id                 :integer          not null, primary key
#  status             :integer          not null
#  created_at         :datetime         not null
#  updated_at         :datetime         not null
#  bill_id            :integer          not null
#  user_legislator_id :integer          not null
#
# Indexes
#
#  index_user_legislator_emails_on_bill_id             (bill_id)
#  index_user_legislator_emails_on_ul_and_bill         (user_legislator_id,bill_id) UNIQUE
#  index_user_legislator_emails_on_user_legislator_id  (user_legislator_id)
#
# Foreign Keys
#
#  bill_id             (bill_id => bills.id)
#  user_legislator_id  (user_legislator_id => user_legislators.id)
#
class UserLegislatorEmail < ApplicationRecord
  enum :status,
    {pending: 0, sending: 1, sent: 2, failed: 3},
    default: :pending

  after_create_commit :queue_send_legislator_email

  belongs_to :user_legislator
  belongs_to :bill

  delegate :legislator, to: :user_legislator
  delegate :user, to: :user_legislator
  delegate :sway_locale, to: :bill

  def user_vote
    @user_vote ||= UserVote.find_by(bill:, user:)
  end

  def sendable?
    # @lat: [[bill-session-archiving#Bill session archiving#Ingestion and pending work]]
    return false unless Bill.exists?(bill_id)

    # @lat: [[outbound-email#Outbound email#A trailing newline reads as a revoked key]]
    EnvSecret.read("RESEND_EMAIL_API_KEY").present? && (pending? || failed?) &&
      legislator.email.present? && user.email_sendable?
  end

  def queue_send_legislator_email
    OnUserEmailSavedSendEmailToLegislatorJob.perform_later(self)
  end

  def send_email
    SwayLogging.info(
      "UserLegislatorEmail.send_email - Sending Email to Legislator: #{legislator.id} for Bill: #{bill.id}"
    )
    sent_mail =
      UserLegislatorEmailMailer.send_email_to_legislator(self).deliver_now! #: untyped

    update!(
      status:
        (
          if sent_mail.error_status.nil?
            UserLegislatorEmail.statuses["sent"]
          else
            UserLegislatorEmail.statuses["failed"]
          end
        )
    )
    true
  end
end
