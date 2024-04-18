# https://medium.com/the-gnar-company/creating-passkey-authentication-in-a-rails-7-application-a0f03f9114c1

require Rails.root.join('lib/devise/strategies/passkey_authenticatable')

module Devise
  module Models
    module PasskeyAuthenticatable
      extend ActiveSupport::Concern
    end
  end
end
