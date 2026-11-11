# frozen_string_literal: true

# @lat: [[phone-cache-hashing]]
module PhoneCacheKey
  class MissingHmacSecretError < StandardError
    MESSAGE =
      "PHONE_CACHE_HMAC_SECRET_KEY is not set (or is blank) in this process's environment, " \
      "so phone numbers can be neither hashed nor matched in the shared cache"

    def initialize(message = MESSAGE)
      super
    end
  end

  ANONYMOUS = "anonymous"

  def self.hmac_secret_key
    return "test" if Rails.env.test?

    EnvSecret.read("PHONE_CACHE_HMAC_SECRET_KEY")
  end

  def self.digest(phone)
    normalized = phone.to_s.normalize_phone.presence
    return ANONYMOUS if normalized.nil?

    secret = hmac_secret_key
    raise MissingHmacSecretError if secret.nil?
    verified_secret = secret #: String

    OpenSSL::HMAC.hexdigest("SHA512", verified_secret, normalized)
  end
end
