# typed: true

# == Schema Information
#
# Table name: refresh_tokens
#
#  id         :integer          not null, primary key
#  expires_at :datetime         not null
#  ip_address :string           not null
#  token      :string           not null
#  user_agent :string           not null
#  created_at :datetime         not null
#  updated_at :datetime         not null
#  user_id    :integer          not null
#
# Indexes
#
#  index_refresh_tokens_on_token    (token) UNIQUE
#  index_refresh_tokens_on_user_id  (user_id)
#
# Foreign Keys
#
#  user_id  (user_id => users.id)
#
class RefreshToken < ApplicationRecord
  extend T::Sig

  belongs_to :user

  class << self
    extend T::Sig

    def token
      SecureRandom.urlsafe_base64(32)
    end

    def expires_at
      Time.zone.now + 1.year
    end

    sig { params(user: User, request: ActionDispatch::Request).returns(RefreshToken) }
    def for(user, request)
      user.refresh_token&.destroy

      RefreshToken.create!(
        user_id: user.id,
        ip_address: request.remote_ip,
        user_agent: request.user_agent,
        token:,
        expires_at:
      )
    end
  end

  sig { returns(T::Boolean) }
  def expired?
    expires_at < Time.zone.now
  end

  sig { params(request: ActionDispatch::Request).returns(T::Boolean) }
  def is_valid?(request)
    !expired? && request.remote_ip == ip_address && request.user_agent == user_agent
  end

  sig { returns(T::Hash[Symbol, T.any(String, T::Boolean, ActiveSupport::TimeWithZone)]) }
  def as_cookie
    {
      value: token,
      httponly: true,
      expires: RefreshToken.expires_at, # Matches refresh token expiry
      secure: Rails.env.production?, # Important for security!
      same_site: "Strict" # Recommended for security
    }
  end
end
