# == Schema Information
#
# Table name: api_keys
# Database name: primary
#
#  id               :integer          not null, primary key
#  bearer_type      :string           not null
#  last_used_on_utc :datetime
#  name             :string
#  token_digest     :string           not null
#  created_at       :datetime         not null
#  updated_at       :datetime         not null
#  bearer_id        :integer          not null
#
# Indexes
#
#  index_api_keys_on_bearer_id_and_bearer_type  (bearer_id,bearer_type)
#  index_api_keys_on_token_digest               (token_digest) UNIQUE
#
# https://keygen.sh/blog/how-to-implement-api-key-authentication-in-rails-without-devise/
class ApiKey < ApplicationRecord
  HMAC_SECRET_KEY = Rails.env.test? ? "test" : ENV["API_KEY_HMAC_SECRET_KEY"]

  belongs_to :bearer, polymorphic: true
  before_create :generate_token_hmac_digest

  # Virtual attribute for raw token value, allowing us to respond with the
  # API key's non-hashed token value. but only directly after creation.
  attr_accessor :token

  def self.authenticate_by_token!(token)
    secret = HMAC_SECRET_KEY
    if secret.nil?
      raise ActiveRecord::RecordInvalid, "HMAC_SECRET_KEY is missing"
    end

    digest = OpenSSL::HMAC.hexdigest "SHA512", secret, token

    find_by! token_digest: digest
  end

  def self.authenticate_by_token(token)
    authenticate_by_token! token
  rescue ActiveRecord::RecordNotFound
    nil
  end

  private

  def generate_token_hmac_digest
    raise(ActiveRecord::RecordInvalid, "token is required") if token.blank?

    secret = HMAC_SECRET_KEY
    if secret.nil?
      raise(ActiveRecord::RecordInvalid, "HMAC_SECRET_KEY is missing")
    end

    digest =
      OpenSSL::HMAC.hexdigest(
        "SHA512",
        secret,
        token, #: String
      )

    self.token_digest = digest
  end
end
