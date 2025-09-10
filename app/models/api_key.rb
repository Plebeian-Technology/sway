# typed: true

# == Schema Information
#
# Table name: api_keys
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
    extend T::Sig

    HMAC_SECRET_KEY = Rails.env.test? ? "test" : ENV["API_KEY_HMAC_SECRET_KEY"]

    belongs_to :bearer, polymorphic: true
    before_create :generate_token_hmac_digest

    # Virtual attribute for raw token value, allowing us to respond with the
    # API key's non-hashed token value. but only directly after creation.
    attr_accessor :token

    sig { params(token: String).returns(T.nilable(ApiKey)) }
    def self.authenticate_by_token!(token)
        digest = OpenSSL::HMAC.hexdigest "SHA512", HMAC_SECRET_KEY, token

        find_by! token_digest: digest
    end

    sig { params(token: String).returns(T.nilable(ApiKey)) }
    def self.authenticate_by_token(token)
        authenticate_by_token! token
    rescue ActiveRecord::RecordNotFound
        nil
    end

    private

    def generate_token_hmac_digest
        raise(ActiveRecord::RecordInvalid, "token is required") if token.blank?

        digest = OpenSSL::HMAC.hexdigest("SHA512", HMAC_SECRET_KEY, token)

        self.token_digest = digest
    end
end
