# typed: true

# == Schema Information
#
# Table name: user_legislator_emails
#
#  id                 :integer          not null, primary key
#  message            :string
#  status             :integer          not null
#  created_at         :datetime         not null
#  updated_at         :datetime         not null
#  bill_id            :integer
#  user_legislator_id :integer          not null
#
# Indexes
#
#  index_user_legislator_emails_on_bill_id             (bill_id)
#  index_user_legislator_emails_on_user_legislator_id  (user_legislator_id)
#
# Foreign Keys
#
#  bill_id             (bill_id => bills.id)
#  user_legislator_id  (user_legislator_id => user_legislators.id)
#
class UserLegislatorEmail < ApplicationRecord
  extend T::Sig

  SENDGRID_TEMPLATE_ID = ""

  enum :status, {pending: 0, sending: 1, sent: 2, failed: 3}, default: :pending

  after_create_commit :queue_send_legislator_email

  belongs_to :user_legislator
  belongs_to :bill

  delegate :legislator, to: :user_legislator
  delegate :user, to: :user_legislator

  sig { returns(Bill) }
  def bill
    T.cast(super, Bill)
  end

  sig { returns(T.nilable(UserVote)) }
  def user_vote
    @_user_vote ||= UserVote.find_by(bill:, user:)
  end

  def sendable?
    ENV["SENDGRID_API_KEY"].present? && (pending? || failed?) && legislator.email.present? && user.email.present?
  end

  def queue_send_legislator_email
    OnUserEmailSavedSendEmailToLegislatorJob.perform_later(self)
  end

  # https://www.twilio.com/docs/sendgrid/for-developers/sending-email/quickstart-ruby
  def send_email
    Rails.logger.info("UserLegislatorEmail.send_email - Sending Email to Legislator: #{legislator.id} for Bill: #{bill.id}")
    response = sg.client.mail._("send").post(request_body: mail.to_json)

    if response.status_code >= 200 && response.status_code < 300
      update(status: UserLegislatorEmail.statuses["sent"])
    else
      Rails.logger.error("UserLegislatorEmail.send_email - FAILED - Received Status Code: #{response.status_code}")
      update(status: UserLegislatorEmail.statuses["failed"])
    end
  end

  private

  # https://www.twilio.com/docs/sendgrid/for-developers/sending-email/quickstart-ruby
  def mail
    mail = SendGrid::Mail.new(from, subject, to, content)
    mail.template_id = SENDGRID_TEMPLATE_ID
    mail.reply_to = reply_to
    mail
  end

  def from
    SendGrid::Email.new(email: "outreach@sway.vote", name: "Sway") # Change to your verified sender
  end

  def reply_to
    user.email
  end

  def to
    legislator_email = legislator.email
    unless Rails.env.production?
      legislator_email = "#{legislator_email.split("@").first}@sway.vote"
    end
    Rails.logger.info("UserLegislatorEmail.to - Legislator Email is: #{legislator_email}")
    SendGrid::Email.new(email: legislator_email, name: legislator.nam) # Change to your recipient
  end

  def subject
    uv = user_vote

    if uv.present?
      "#{(uv.support == "FOR") ? "Support" : "Oppose"} Bill #{bill.external_id}"
    else
      "Bill #{bill.external_id}"
    end
  end

  def content
    SendGrid::Content.new(type: "text/plain", value: message)
  end

  def sg
    @_sg ||= SendGrid::API.new(api_key: ENV["SENDGRID_API_KEY"])
  end
end
