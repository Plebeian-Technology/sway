# == Schema Information
#
# Table name: api_keys
# Database name: primary
#
#  id               :integer          not null, primary key
#  bearer_type      :string           not null
#  expires_at       :datetime
#  last_used_on_utc :datetime
#  name             :string
#  token_digest     :string           not null
#  created_at       :datetime         not null
#  updated_at       :datetime         not null
#  bearer_id        :integer          not null
#  user_device_id   :integer
#
# Indexes
#
#  index_api_keys_on_bearer_id_and_bearer_type  (bearer_id,bearer_type)
#  index_api_keys_on_expires_at                 (expires_at)
#  index_api_keys_on_token_digest               (token_digest) UNIQUE
#  index_api_keys_on_user_device_id             (user_device_id)
#
# Foreign Keys
#
#  user_device_id  (user_device_id => user_devices.id)
#
# https://keygen.sh/blog/how-to-implement-api-key-authentication-in-rails-without-devise/
class ApiKey < ApplicationRecord
  # @lat: [[api-key-hmac-secret-handling#Why MissingHmacSecretError is a plain StandardError]]
  class MissingHmacSecretError < StandardError
    MESSAGE =
      "API_KEY_HMAC_SECRET_KEY is not set (or is blank) in this process's environment, " \
      "so API keys can be neither minted nor verified"

    def initialize(message = MESSAGE)
      super
    end
  end

  # @lat: [[api-key-hmac-secret-handling#Why hmac_secret_key is a method, not a constant]]
  def self.hmac_secret_key
    return "test" if Rails.env.test?

    EnvSecret.read("API_KEY_HMAC_SECRET_KEY")
  end

  belongs_to :bearer, polymorphic: true
  belongs_to :user_device, optional: true
  before_create :generate_token_hmac_digest

  # @lat: [[api-key-hmac-secret-handling#Why the token-blank check raises RecordInvalid, but the missing-secret check doesn't]]
  attr_accessor :token

  # @lat: [[api-key-hmac-secret-handling#Why an ApiKey's active? check covers user_device revocation]]
  def active?
    exp = expires_at
    not_expired = exp.nil? || exp > Time.current

    dev = user_device
    device_ok = dev.nil? || dev.revoked_at.nil?

    not_expired && device_ok
  end

  # @lat: [[api-key-hmac-secret-handling#What ApiKey.to_builder sends, and what it withholds]]
  def to_builder
    Jbuilder.new do |b|
      b.id id
      b.name name
      b.created_at created_at
      b.last_used_on_utc last_used_on_utc
    end
  end

  def self.authenticate_by_token!(token)
    secret = hmac_secret_key
    raise MissingHmacSecretError if secret.nil?
    verified_secret = secret #: String

    digest = OpenSSL::HMAC.hexdigest "SHA512", verified_secret, token

    api_key = find_by!(token_digest: digest)
    raise ActiveRecord::RecordNotFound unless api_key.active?

    api_key
  end

  def self.authenticate_by_token(token)
    authenticate_by_token! token
  rescue ActiveRecord::RecordNotFound
    nil
  end

  private

  def generate_token_hmac_digest
    # @lat: [[api-key-hmac-secret-handling#Why the token-blank check raises RecordInvalid, but the missing-secret check doesn't]]
    if token.blank?
      errors.add(:token, :blank)
      raise ActiveRecord::RecordInvalid.new(self)
    end

    secret = self.class.hmac_secret_key
    raise MissingHmacSecretError if secret.nil?
    verified_secret = secret #: String

    digest =
      OpenSSL::HMAC.hexdigest(
        "SHA512",
        verified_secret,
        token #: String
      )

    self.token_digest = digest
  end
end
