# frozen_string_literal: true

# @lat: [[twilio-inbound-opt-out-webhook#Why an unknown phone number returns success, not an error]]
class SmsOptOutService
  STOP_KEYWORDS = SmsKeywords::STOP
  START_KEYWORDS = SmsKeywords::START

  def initialize(from:, body:)
    @from = from
    @body = body
  end

  def call
    enabled = target_state
    return if enabled.nil?

    user = User.find_by(phone: @from.to_s.normalize_phone)
    return unless user

    # @lat: [[twilio-inbound-opt-out-webhook#Why the flag write skips validations and callbacks]]
    user.update_columns(sms_notifications_enabled: enabled, updated_at: Time.current)
  end

  private

  def target_state
    keyword = SmsKeywords.normalize(@body)
    return false if STOP_KEYWORDS.include?(keyword)
    return true if START_KEYWORDS.include?(keyword)

    nil
  end
end
