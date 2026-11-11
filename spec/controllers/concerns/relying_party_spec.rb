# frozen_string_literal: true

require "rails_helper"

# @lat: [[webauthn-rp-id-settings-resolution#Why spec/controllers/concerns/relying_party_spec.rb is a new file, not a migration]]
RSpec.describe RelyingParty, type: :controller do
  controller(ActionController::Base) do
    include RelyingParty

    def index
      rp = relying_party
      render json: {id: rp.id, name: rp.name, allowed_origins: rp.allowed_origins}
    end
  end

  before do
    routes.draw { get "/relying_party", to: "anonymous#index" }
  end

  after { Sway::Settings.reset! }

  def rp_response_body
    JSON.parse(response.body)
  end

  def stub_rails_env(name)
    allow(Rails).to receive(:env).and_return(ActiveSupport::StringInquirer.new(name))
  end

  describe "the relying party domain (WEBAUTHN_RP_ID)" do
    it "uses the setting when it is set, and the log line reports the setting as the source" do
      expect(SwayLogging).to receive(:info).with(a_string_matching(/rp_id_source=env/))

      with_app_config(:webauthn, rp_id: "custom.sway.example") do
        get :index
      end

      expect(rp_response_body["id"]).to eq("custom.sway.example")
    end

    # @lat: [[webauthn-settings-consolidation#Why rp_id has no default]]
    it "refuses a ceremony in production when the setting is unset, rather than guessing a domain" do
      stub_rails_env("production")

      with_app_config(:webauthn, rp_id: nil, allowed_origins: ["https://custom.example"]) do
        expect { get :index }.to raise_error(Sway::Settings::MissingValues, /WEBAUTHN_RP_ID/)
      end
    end

    it "falls back to the request's own host outside production, and the log line says the domain was derived" do
      stub_rails_env("development")
      expect(SwayLogging).to receive(:info).with(a_string_matching(/rp_id_source=derived_from_origin/))

      with_app_config(:webauthn, rp_id: nil) do
        get :index
      end

      expect(rp_response_body["id"]).to eq(request.host)
    end
  end

  describe "the allowed origins (WEBAUTHN_ALLOWED_ORIGINS)" do
    before { stub_app_config(:mobile, android_cert_sha256_fingerprints: []) }

    it "uses exactly the configured origins when set" do
      with_app_config(:webauthn, allowed_origins: ["https://custom.example"]) do
        get :index
      end

      expect(rp_response_body["allowed_origins"]).to eq(["https://custom.example"])
    end

    it "refuses a ceremony in production when unset, rather than guessing origins" do
      stub_rails_env("production")

      with_app_config(:webauthn, allowed_origins: [], rp_id: "custom.example") do
        expect { get :index }.to raise_error(Sway::Settings::MissingValues, /WEBAUTHN_ALLOWED_ORIGINS/)
      end
    end

    it "uses the request's own origin outside production when unset" do
      stub_rails_env("development")

      with_app_config(:webauthn, allowed_origins: []) do
        get :index
      end

      expect(rp_response_body["allowed_origins"]).to eq(["#{request.protocol}#{request.host_with_port}"])
    end

    it "appends one android apk-key-hash origin per configured certificate fingerprint" do
      stub_app_config(:mobile, android_cert_sha256_fingerprints: ["AA:BB"])

      with_app_config(:webauthn, allowed_origins: ["https://custom.example"]) do
        get :index
      end

      expect(rp_response_body["allowed_origins"]).to eq(["https://custom.example", "android:apk-key-hash:qrs"])
    end
  end

  describe "the relying party name" do
    it "is built from the environment Rails is running in, with no trailing hyphen and nothing after it" do
      get :index

      expect(rp_response_body["name"]).to eq("sway-#{Rails.env}")
      expect(rp_response_body["name"]).not_to end_with("-")
    end
  end

  # @lat: [[webauthn-rp-id-settings-resolution#Why spec/controllers/concerns/relying_party_spec.rb is a new file, not a migration]]
  describe "the name is built from Rails.env alone, with no environment-variable-driven suffix" do
    it "no longer reads IS_PREVIEW, and no longer builds a -preview suffix" do
      source = Rails.root.join("app", "controllers", "concerns", "relying_party.rb").read

      expect(source).not_to include("IS_PREVIEW")
      expect(source).not_to include("-preview")
    end
  end
end
