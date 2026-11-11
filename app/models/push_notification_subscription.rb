# frozen_string_literal: true

# == Schema Information
#
# Table name: push_notification_subscriptions
# Database name: primary
#
#  id         :integer          not null, primary key
#  auth       :string
#  endpoint   :string
#  p256dh     :string
#  subscribed :boolean          default(FALSE), not null
#  created_at :datetime         not null
#  updated_at :datetime         not null
#  user_id    :integer          not null
#
# Indexes
#
#  index_push_notification_subscriptions_on_user_id_and_endpoint  (user_id,endpoint) UNIQUE
#
# Foreign Keys
#
#  user_id  (user_id => users.id)
#
class PushNotificationSubscription < ApplicationRecord
  ALLOWED_ENDPOINT_DOMAINS = %w[
    push.apple.com
    fcm.googleapis.com
    googleapis.com
    push.services.mozilla.com
    notify.windows.com
  ].freeze

  TEST_ENDPOINT_DOMAINS = %w[
    sway.vote
    example.com
    push.example
  ].freeze

  belongs_to :user

  validates :endpoint, presence: true
  validate :validate_endpoint_url

  scope :active, -> { where(subscribed: true) }

  # @lat: [[push-notification-subscription-design#Why to_builder withholds auth and p256dh]]
  def to_builder
    Jbuilder.new do |b|
      b.id id
      b.endpoint endpoint
      b.subscribed subscribed
      b.created_at created_at
    end
  end

  def send_web_push_notification(message)
    endpoint_value = endpoint
    p256dh_value = p256dh
    auth_value = auth
    vapid_value = vapid

    return if endpoint_value.nil? || p256dh_value.nil? || auth_value.nil?
    private_key = vapid_value[:private_key]
    public_key = vapid_value[:public_key]
    subject = vapid_value[:subject]

    return if private_key.nil? || public_key.nil? || subject.nil?

    WebPush.payload_send(
      message: JSON.generate(message),
      endpoint: endpoint_value,
      p256dh: p256dh_value,
      auth: auth_value,
      urgency: "high", # optional, it can be very-low, low, normal, high, defaults to normal
      open_timeout: 5,
      read_timeout: 5,
      vapid: {
        private_key:,
        public_key:,
        subject:
      }
    )
  rescue => e
    SwayLogging.log_exception(
      "push_notification_subscription.send_failed",
      exception: e,
      subscription_id: id,
      user_id: user_id,
      endpoint_host: endpoint_host
    )
  end

  private

  def validate_endpoint_url
    raw = endpoint.to_s.strip
    return if raw.blank?

    uri = URI.parse(raw)
    unless uri.is_a?(URI::HTTPS) && allowed_endpoint_host?(uri.host)
      errors.add(:endpoint, "must be an https:// URL on an allowed Web Push host")
    end
  rescue URI::InvalidURIError
    errors.add(:endpoint, "is not a valid URL")
  end

  def allowed_endpoint_host?(host)
    normalized = host.to_s.downcase.chomp(".")
    return false if normalized.blank?

    domains = Rails.env.test? ? (ALLOWED_ENDPOINT_DOMAINS + TEST_ENDPOINT_DOMAINS) : ALLOWED_ENDPOINT_DOMAINS
    domains.any? do |domain|
      normalized == domain || normalized.end_with?(".#{domain}")
    end
  end

  def vapid
    @vapid ||= {
      subject: "mailto:github@sway.vote",
      # @lat: [[push-notification-subscription-design#Why the VAPID keys must never carry a trailing newline]]
      public_key: EnvSecret.read("VAPID_PUBLIC_KEY"),
      private_key: EnvSecret.read("VAPID_PRIVATE_KEY")
    }
  end

  def endpoint_host
    URI.parse(endpoint.to_s).host
  rescue URI::InvalidURIError
    nil
  end
end
