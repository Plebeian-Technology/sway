# frozen_string_literal: true

# @lat: [[phone-cache-hashing]]
module EmailCacheKey
  MissingHmacSecretError = PhoneCacheKey::MissingHmacSecretError

  ANONYMOUS = "anonymous"

  def self.hmac_secret_key
    PhoneCacheKey.hmac_secret_key
  end

  def self.digest(raw_email)
    normalized = raw_email.to_s.strip.downcase.presence
    return ANONYMOUS if normalized.nil?

    secret = hmac_secret_key
    raise MissingHmacSecretError if secret.nil?
    verified_secret = secret #: String

    OpenSSL::HMAC.hexdigest("SHA512", verified_secret, normalized)
  end
end
