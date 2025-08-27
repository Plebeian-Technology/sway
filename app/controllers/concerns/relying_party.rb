# frozen_string_literal: true
# typed: true

module RelyingParty
  extend ActiveSupport::Concern
  extend T::Sig

  # https://github.com/ruby-passkeys/devise-passkeys-template/blob/329990739ffffcd9306ceff775c1561cead71029/app/controllers/concerns/relying_party.rb#L4

  included do
    def relying_party
      Rails.logger.info("RelyingParty.relying_party.origin - #{"#{T.unsafe(self).request.protocol}#{T.unsafe(self).request.host}"}")

      WebAuthn::RelyingParty.new(
        # This value needs to match `window.location.origin` evaluated by
        # the User Agent during registration and authentication ceremonies.
        # origin: Rails.env.production? ? "https://app.sway.vote" : "https://localhost:3333",
        allowed_origins: origins,

        # Relying Party name for display purposes
        name: "sway-#{ENV["RAILS_ENV"]}",
        # Optionally configure a client timeout hint, in milliseconds.
        # This hint specifies how long the browser should wait for any
        # interaction with the user.
        # This hint may be overridden by the browser.
        # https://www.w3.org/TR/webauthn/#dom-publickeycredentialcreationoptions-timeout
        credential_options_timeout: 120_000,

        # You can optionally specify a different Relying Party ID
        # (https://www.w3.org/TR/webauthn/#relying-party-identifier)
        # if it differs from the default one.
        #
        # In this case the default would be "admin.example.com", but you can set it to
        # the suffix "example.com"
        #
        id: Rails.env.production? ? "app.sway.vote" : nil
        # Configure preferred binary-to-text encoding scheme. This should match the encoding scheme
        # used in your client-side (user agent) code before sending the credential to the server.
        # Supported values: `:base64url` (default), `:base64` or `false` to disable all encoding.
        #
        # encoding: :base64url

        # Possible values: "ES256", "ES384", "ES512", "PS256", "PS384", "PS512", "RS256", "RS384", "RS512", "RS1"
        # Default: ["ES256", "PS256", "RS256"]
        #
        # algorithms: ["ES384"]
      )
    end

    private

    def origins
      if Rails.env.production?
        ["#{T.unsafe(self).request.protocol}#{T.unsafe(self).request.host}"]
      else
        ["#{T.unsafe(self).request.protocol}#{T.unsafe(self).request.host_with_port}"]
      end
    end
  end
end
