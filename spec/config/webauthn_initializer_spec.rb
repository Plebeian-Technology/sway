# frozen_string_literal: true

require "rails_helper"

# @lat: [[webauthn-settings-consolidation#How spec/config/webauthn_initializer_spec.rb tests a boot-time initializer]]
RSpec.describe "config/initializers/webauthn.rb" do
  after { Sway::Settings.reset! }

  around do |example|
    original_allowed_origins = WebAuthn.configuration.allowed_origins&.dup
    original_rp_id = WebAuthn.configuration.rp_id

    begin
      example.run
    ensure
      WebAuthn.configuration.allowed_origins = original_allowed_origins
      WebAuthn.configuration.rp_id = original_rp_id
    end
  end

  def load_initializer(env)
    allow(Rails).to receive(:env).and_return(ActiveSupport::StringInquirer.new(env))
    load Rails.root.join("config", "initializers", "webauthn.rb").to_s
  end

  describe "the allowed origins (WEBAUTHN_ALLOWED_ORIGINS)" do
    it "is configured with exactly the setting's origins when set" do
      with_app_config(:webauthn, allowed_origins: ["https://custom.example"]) do
        load_initializer("test")
      end

      expect(WebAuthn.configuration.allowed_origins).to eq(["https://custom.example"])
    end

    it "is configured with exactly the setting's origins in production" do
      with_app_config(:webauthn, allowed_origins: ["https://custom.example"], rp_id: "custom.example") do
        load_initializer("production")
      end

      expect(WebAuthn.configuration.allowed_origins).to eq(["https://custom.example"])
    end

    # @lat: [[webauthn-settings-consolidation#Why production names its origins and domain in the deploy file]]
    it "refuses to boot production when the setting is unset, naming the missing variable" do
      with_app_config(:webauthn, allowed_origins: [], rp_id: "custom.example") do
        expect { load_initializer("production") }
          .to raise_error(Sway::Settings::MissingValues, /WEBAUTHN_ALLOWED_ORIGINS/)
      end
    end

    it "does not stop an image build, which boots production with every required check switched off" do
      previous = Anyway::Settings.suppress_required_validations
      Anyway::Settings.suppress_required_validations = true
      with_app_config(:webauthn, allowed_origins: [], rp_id: nil) do
        expect { load_initializer("production") }.not_to raise_error
      end

      expect(WebAuthn.configuration.allowed_origins).to eq([])
    ensure
      Anyway::Settings.suppress_required_validations = previous
    end

    it "falls back to the four local addresses when unset outside production" do
      with_app_config(:webauthn, allowed_origins: []) do
        load_initializer("development")
      end

      expect(WebAuthn.configuration.allowed_origins).to contain_exactly(
        "https://localhost:3333",
        "http://localhost:3333",
        "https://localhost:3000",
        "http://localhost:3000"
      )
    end
  end

  describe "the relying party domain (WEBAUTHN_RP_ID)" do
    it "is configured with the setting when it is set" do
      with_app_config(:webauthn, rp_id: "custom.sway.example") do
        load_initializer("test")
      end

      expect(WebAuthn.configuration.rp_id).to eq("custom.sway.example")
    end

    it "refuses to boot production when the setting is unset, naming the missing variable" do
      with_app_config(:webauthn, allowed_origins: ["https://custom.example"], rp_id: nil) do
        expect { load_initializer("production") }
          .to raise_error(Sway::Settings::MissingValues, /WEBAUTHN_RP_ID/)
      end
    end

    # The deliberate difference from RelyingParty#relying_party: the
    # library setup runs once at startup with no request, so it cannot name a
    # host the way the concern can. Left nil, the library works the domain
    # out from the first allowed origin at ceremony time.
    it "is left unset outside production, so the library works the domain out from the first allowed origin" do
      with_app_config(:webauthn, rp_id: nil) do
        load_initializer("development")
      end

      expect(WebAuthn.configuration.rp_id).to be_nil
    end
  end
end
