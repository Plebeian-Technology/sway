# frozen_string_literal: true

# @lat: [[registration-funnel-telemetry#Event schema and database storage]]
# == Schema Information
#
# Table name: registration_funnel_events
# Database name: primary
#
#  id              :integer          not null, primary key
#  attribution_key :string(100)
#  bot             :boolean          default(FALSE), not null
#  metadata        :json             not null
#  step            :integer          not null
#  visitor_token   :string(64)       not null
#  created_at      :datetime         not null
#  user_id         :integer
#
# Indexes
#
#  index_registration_funnel_events_on_attribution_and_created_at  (attribution_key,created_at)
#  index_registration_funnel_events_on_bot_step_created_at         (bot,step,created_at)
#  index_registration_funnel_events_on_step_and_created_at         (step,created_at)
#  index_registration_funnel_events_on_user_id                     (user_id)
#  index_registration_funnel_events_on_visitor_token               (visitor_token)
#
# Foreign Keys
#
#  user_id  (user_id => users.id) ON DELETE => nullify
#
class RegistrationFunnelEvent < ApplicationRecord
  belongs_to :user, optional: true

  enum :step, {
    landing: 0,
    phone_submitted: 1,
    sms_verified: 2,
    passkey_enrolled: 3,
    address_submitted: 4,
    geocoding_queued: 5,
    geocoding_completed: 6,
    geocoding_failed: 7,
    first_vote_cast: 8
  }

  STEP_ALIASES = {
    "phone_entered" => "phone_submitted",
    "registration_completed" => "geocoding_completed"
  }.freeze

  validates :visitor_token, presence: true, length: {maximum: 64}
  validates :step, presence: true
  validates :attribution_key, length: {maximum: 100}, allow_nil: true

  scope :recent, -> { order(created_at: :desc) }
  scope :humans, -> { where(bot: false) }
  scope :bots, -> { where(bot: true) }

  # @lat: [[registration-funnel-telemetry#Bot traffic classification]]
  def self.bot_traffic?(user:, user_agent: nil)
    return user.is_sway_api_user? if user

    BotUserAgent.bot?(user_agent)
  end

  # @lat: [[registration-funnel-telemetry#Bot traffic classification#Verified users reclassify their visitor token]]
  def self.mark_visitor_human!(visitor_token)
    return 0 if visitor_token.blank?

    where(visitor_token: visitor_token, bot: true).update_all(bot: false)
  end

  def self.normalize_step(val)
    str = val.to_s
    STEP_ALIASES.fetch(str, str)
  end

  def step=(val)
    write_attribute(:step, self.class.normalize_step(val))
  end

  def latency_ms
    metadata&.dig("latency_ms") || metadata&.dig(:latency_ms)
  end

  def latency_ms=(val)
    self.metadata = (metadata || {}).merge("latency_ms" => val)
  end
end
