# frozen_string_literal: true

# @lat: [[sms-verification-token-design#The replay defense]]
class SmsVerificationToken
  TTL = 10.minutes
  KEY_PREFIX = "sms_verified_token"

  def self.issue!(phone)
    token = SecureRandom.hex(32)
    Rails.cache.write(
      "#{KEY_PREFIX}:#{token}",
      {phone: PhoneCacheKey.digest(phone), issued_at: Time.current.to_i},
      expires_in: TTL
    )
    token
  end

  # @lat: [[sms-verification-token-design#The replay defense]]
  def self.consume!(token, phone:)
    return false if token.blank?

    key = "#{KEY_PREFIX}:#{token}"
    stored = Rails.cache.read(key)
    return false unless stored

    return false unless Rails.cache.delete(key)

    stored_digest = stored[:phone].to_s
    expected_digest = PhoneCacheKey.digest(phone)
    return false if stored_digest.blank? || stored_digest.bytesize != expected_digest.bytesize

    ActiveSupport::SecurityUtils.secure_compare(stored_digest, expected_digest)
  end

  # @lat: [[sms-verification-token-design#Why peek exists alongside consume!]]
  def self.peek(token)
    return nil if token.blank?

    Rails.cache.read("#{KEY_PREFIX}:#{token}")
  end
end
