class UserLegislatorEmailMailer < ApplicationMailer
  # @lat: [[outbound-email#Why mailers default to outreach@sway.vote and bake invite expiry into signed tokens]]
  default from: "outreach@sway.vote"

  helper_method :intro, :body, :conclusion, :bill_link

  # @lat: [[outbound-email#Outbound email#The preview is built from the object the mailer renders]]
  delegate :intro, :body, :conclusion, :subject, :bill_link, to: :text

  def send_email_to_legislator(user_legislator_email)
    @user_legislator_email = user_legislator_email

    mail(
      from:,
      to: to,
      cc: user.email,
      reply_to:,
      subject: subject,
      track_opens: true,
      track_clicks: true
    )
  end

  private

  def text
    @text ||= LegislatorEmailText.new(@user_legislator_email)
  end

  def from
    "outreach@sway.vote"
  end

  def reply_to
    @user_legislator_email.user.email
  end

  def to
    legislator_email = legislator.email
    return nil if legislator_email.nil?

    unless Rails.env.production?
      legislator_email =
        "#{legislator_email.split("@").first}@sway.vote"
    end
    SwayLogging.info(
      "UserLegislatorEmail.to - Legislator Email is: #{legislator_email}"
    )
    legislator_email
  end

  def legislator
    @legislator ||= @user_legislator_email.legislator
  end

  def user
    @user ||= @user_legislator_email.user
  end

  def bill
    @bill ||= @user_legislator_email.bill
  end
end
