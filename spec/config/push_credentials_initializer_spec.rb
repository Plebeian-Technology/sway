# frozen_string_literal: true

require "rails_helper"

# @lat: [[multiline-credentials-over-kamal#Why multiline credentials travel as Base64]]
RSpec.describe "config/initializers/apns.rb and config/initializers/fcm.rb" do
  # Generated per example rather than embedded: a PEM literal here is a
  # private-key finding for gitleaks, whose rule matches the armor line.
  let(:fake_apns_key_pem) { OpenSSL::PKey::EC.generate("prime256v1").private_to_pem }

  let(:fake_sandbox_apns_key_pem) { OpenSSL::PKey::EC.generate("prime256v1").private_to_pem }

  let(:fake_fcm_service_account_json) do
    %({"type":"service_account","project_id":"sway-test","private_key":"#{fake_apns_key_pem.gsub("\n", '\n')}"})
  end

  around do |example|
    original_apns = Rails.application.config.apns
    original_fcm = Rails.application.config.fcm

    begin
      example.run
    ensure
      Rails.application.config.apns = original_apns
      Rails.application.config.fcm = original_fcm
    end
  end

  def load_apns_initializer
    load Rails.root.join("config", "initializers", "apns.rb").to_s
  end

  def load_fcm_initializer
    load Rails.root.join("config", "initializers", "fcm.rb").to_s
  end

  describe "config.apns" do
    around do |example|
      with_app_config(:mobile, apple_team_id: "ABCDE12345", apple_bundle_id: "app.example.test") { example.run }
    end

    it "takes the team and bundle ids from the mobile settings group" do
      load_apns_initializer

      expect(Rails.application.config.apns.team_id).to eq("ABCDE12345")
      expect(Rails.application.config.apns.bundle_id).to eq("app.example.test")
    end

    it "is disabled when APPLE_TEAM_ID is unset, even with a valid key pair" do
      with_app_config(:mobile, apple_team_id: nil, apple_bundle_id: "app.example.test") do
        with_env(
          "APNS_ENV" => "production",
          "APNS_AUTH_KEY_P8" => Base64.strict_encode64(fake_apns_key_pem),
          "APNS_KEY_ID" => "ABC123DEFG"
        ) do
          load_apns_initializer
        end
      end

      expect(Rails.application.config.apns.team_id).to be_nil
      expect(Rails.application.config.apns.enabled).to be(false)
    end

    it "is disabled when APPLE_BUNDLE_ID is unset, even with a valid key pair" do
      with_app_config(:mobile, apple_team_id: "ABCDE12345", apple_bundle_id: nil) do
        with_env(
          "APNS_ENV" => "production",
          "APNS_AUTH_KEY_P8" => Base64.strict_encode64(fake_apns_key_pem),
          "APNS_KEY_ID" => "ABC123DEFG"
        ) do
          load_apns_initializer
        end
      end

      expect(Rails.application.config.apns.enabled).to be(false)
    end

    it "is enabled with the decoded PEM when APNS_AUTH_KEY_P8 is valid Base64 and APNS_KEY_ID is present" do
      with_env(
        "APNS_ENV" => "production",
        "APNS_AUTH_KEY_P8" => Base64.strict_encode64(fake_apns_key_pem),
        "APNS_KEY_ID" => "ABC123DEFG"
      ) do
        load_apns_initializer
      end

      expect(Rails.application.config.apns.auth_key_p8).to eq(fake_apns_key_pem.strip)
      expect(Rails.application.config.apns.enabled).to be(true)
    end

    it "is disabled when APNS_AUTH_KEY_P8 is not valid Base64, even with APNS_KEY_ID present" do
      with_env(
        "APNS_ENV" => "production",
        "APNS_AUTH_KEY_P8" => fake_apns_key_pem,
        "APNS_KEY_ID" => "ABC123DEFG"
      ) do
        load_apns_initializer
      end

      expect(Rails.application.config.apns.auth_key_p8).to be_nil
      expect(Rails.application.config.apns.enabled).to be(false)
    end

    it "is disabled when APNS_KEY_ID is missing, even with a decodable key" do
      with_env(
        "APNS_ENV" => "production",
        "APNS_AUTH_KEY_P8" => Base64.strict_encode64(fake_apns_key_pem),
        "APNS_KEY_ID" => nil
      ) do
        load_apns_initializer
      end

      expect(Rails.application.config.apns.enabled).to be(false)
    end

    it "is disabled when both credentials are unset" do
      with_env(
        "APNS_AUTH_KEY_P8" => nil,
        "APNS_KEY_ID" => nil,
        "APNS_SANDBOX_AUTH_KEY_P8" => nil,
        "APNS_SANDBOX_KEY_ID" => nil
      ) do
        load_apns_initializer
      end

      expect(Rails.application.config.apns.auth_key_p8).to be_nil
      expect(Rails.application.config.apns.enabled).to be(false)
    end

    it "uses the production pair and ignores the sandbox pair when APNS_ENV is production" do
      with_env(
        "APNS_ENV" => "production",
        "APNS_AUTH_KEY_P8" => Base64.strict_encode64(fake_apns_key_pem),
        "APNS_KEY_ID" => "ABC123DEFG",
        "APNS_SANDBOX_AUTH_KEY_P8" => Base64.strict_encode64(fake_sandbox_apns_key_pem),
        "APNS_SANDBOX_KEY_ID" => "SBX456DEFG"
      ) do
        load_apns_initializer
      end

      expect(Rails.application.config.apns.env).to eq("production")
      expect(Rails.application.config.apns.auth_key_p8).to eq(fake_apns_key_pem.strip)
      expect(Rails.application.config.apns.key_id).to eq("ABC123DEFG")
      expect(Rails.application.config.apns.enabled).to be(true)
    end

    it "uses the sandbox pair and leaves c.env as development when APNS_ENV is unset" do
      with_env(
        "APNS_ENV" => nil,
        "APNS_AUTH_KEY_P8" => Base64.strict_encode64(fake_apns_key_pem),
        "APNS_KEY_ID" => "ABC123DEFG",
        "APNS_SANDBOX_AUTH_KEY_P8" => Base64.strict_encode64(fake_sandbox_apns_key_pem),
        "APNS_SANDBOX_KEY_ID" => "SBX456DEFG"
      ) do
        load_apns_initializer
      end

      expect(Rails.application.config.apns.env).to eq("development")
      expect(Rails.application.config.apns.auth_key_p8).to eq(fake_sandbox_apns_key_pem.strip)
      expect(Rails.application.config.apns.key_id).to eq("SBX456DEFG")
      expect(Rails.application.config.apns.enabled).to be(true)
    end

    it "uses the sandbox pair when APNS_ENV is explicitly development" do
      with_env(
        "APNS_ENV" => "development",
        "APNS_SANDBOX_AUTH_KEY_P8" => Base64.strict_encode64(fake_sandbox_apns_key_pem),
        "APNS_SANDBOX_KEY_ID" => "SBX456DEFG"
      ) do
        load_apns_initializer
      end

      expect(Rails.application.config.apns.env).to eq("development")
      expect(Rails.application.config.apns.auth_key_p8).to eq(fake_sandbox_apns_key_pem.strip)
      expect(Rails.application.config.apns.enabled).to be(true)
    end

    it "is disabled when only the production pair is present but APNS_ENV is development" do
      with_env(
        "APNS_ENV" => "development",
        "APNS_AUTH_KEY_P8" => Base64.strict_encode64(fake_apns_key_pem),
        "APNS_KEY_ID" => "ABC123DEFG",
        "APNS_SANDBOX_AUTH_KEY_P8" => nil,
        "APNS_SANDBOX_KEY_ID" => nil
      ) do
        load_apns_initializer
      end

      expect(Rails.application.config.apns.auth_key_p8).to be_nil
      expect(Rails.application.config.apns.enabled).to be(false)
    end

    it "is disabled when only the sandbox pair is present but APNS_ENV is production" do
      with_env(
        "APNS_ENV" => "production",
        "APNS_AUTH_KEY_P8" => nil,
        "APNS_KEY_ID" => nil,
        "APNS_SANDBOX_AUTH_KEY_P8" => Base64.strict_encode64(fake_sandbox_apns_key_pem),
        "APNS_SANDBOX_KEY_ID" => "SBX456DEFG"
      ) do
        load_apns_initializer
      end

      expect(Rails.application.config.apns.auth_key_p8).to be_nil
      expect(Rails.application.config.apns.enabled).to be(false)
    end
  end

  describe "config.fcm" do
    it "is enabled with the decoded JSON when FCM_SERVICE_ACCOUNT_JSON is valid Base64 and FCM_PROJECT_ID is present" do
      with_env(
        "FCM_PROJECT_ID" => "sway-test",
        "FCM_SERVICE_ACCOUNT_JSON" => Base64.strict_encode64(fake_fcm_service_account_json)
      ) do
        load_fcm_initializer
      end

      expect(Rails.application.config.fcm.service_account_json).to eq(fake_fcm_service_account_json)
      expect(Rails.application.config.fcm.enabled).to be(true)
    end

    it "is disabled when FCM_SERVICE_ACCOUNT_JSON is not valid Base64, even with FCM_PROJECT_ID present" do
      with_env(
        "FCM_PROJECT_ID" => "sway-test",
        "FCM_SERVICE_ACCOUNT_JSON" => fake_fcm_service_account_json
      ) do
        load_fcm_initializer
      end

      expect(Rails.application.config.fcm.service_account_json).to be_nil
      expect(Rails.application.config.fcm.enabled).to be(false)
    end

    it "is disabled when FCM_PROJECT_ID is missing, even with decodable JSON" do
      with_env(
        "FCM_PROJECT_ID" => nil,
        "FCM_SERVICE_ACCOUNT_JSON" => Base64.strict_encode64(fake_fcm_service_account_json)
      ) do
        load_fcm_initializer
      end

      expect(Rails.application.config.fcm.enabled).to be(false)
    end

    it "is disabled when FCM_PROJECT_ID still carries the deploy placeholder" do
      with_env(
        "FCM_PROJECT_ID" => "<firebase-project-id>",
        "FCM_SERVICE_ACCOUNT_JSON" => Base64.strict_encode64(fake_fcm_service_account_json)
      ) do
        load_fcm_initializer
      end

      expect(Rails.application.config.fcm.project_id).to be_nil
      expect(Rails.application.config.fcm.enabled).to be(false)
    end

    it "is disabled when both credentials are unset" do
      with_env("FCM_PROJECT_ID" => nil, "FCM_SERVICE_ACCOUNT_JSON" => nil) do
        load_fcm_initializer
      end

      expect(Rails.application.config.fcm.service_account_json).to be_nil
      expect(Rails.application.config.fcm.enabled).to be(false)
    end
  end
end
