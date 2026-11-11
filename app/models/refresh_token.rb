# == Schema Information
#
# Table name: refresh_tokens
# Database name: primary
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
  belongs_to :user

  encrypts :ip_address

  class << self
    def token
      SecureRandom.urlsafe_base64(32)
    end

    def expires_at
      1.year.from_now
    end

    # @lat: [[identity-and-access#Sessions, cookies and bearer tokens#Refresh tokens bind to their issuing request]]
    def for(user, request)
      transaction do
        RefreshToken.where(user_id: user.id).destroy_all

        RefreshToken.create!(
          user_id: user.id,
          ip_address: request.remote_ip,
          user_agent: request.user_agent,
          token:,
          expires_at:
        )
      end
    end
  end

  def expired?
    expires_at < Time.zone.now
  end

  # @lat: [[identity-and-access#Sessions, cookies and bearer tokens#Refresh tokens bind to their issuing request]]
  def usable_for?(request)
    !expired? && request.remote_ip == ip_address &&
      request.user_agent == user_agent
  end

  def as_cookie
    {
      value: token,
      httponly: true,
      expires: RefreshToken.expires_at,
      secure: Rails.env.production?,
      same_site: "Strict"
    }
  end
end
