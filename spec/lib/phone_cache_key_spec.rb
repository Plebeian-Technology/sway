# frozen_string_literal: true

require "rails_helper"

RSpec.describe PhoneCacheKey do
  describe ".digest" do
    it "returns the same digest for two spellings of the same number" do
      expect(described_class.digest("(410) 555-1234")).to eq(described_class.digest("4105551234"))
    end

    it "returns different digests for different numbers" do
      expect(described_class.digest("4105551234")).not_to eq(described_class.digest("4105559999"))
    end

    it "never returns the phone number itself" do
      expect(described_class.digest("4105551234")).not_to eq("4105551234")
    end

    it "returns the anonymous bucket for a blank phone" do
      expect(described_class.digest("")).to eq("anonymous")
      expect(described_class.digest(nil)).to eq("anonymous")
    end
  end

  describe ".hmac_secret_key" do
    it "resolves to the fixed test secret under RAILS_ENV=test" do
      with_env("PHONE_CACHE_HMAC_SECRET_KEY" => nil) do
        expect(described_class.hmac_secret_key).to eq("test")
      end
    end

    it "reads PHONE_CACHE_HMAC_SECRET_KEY outside RAILS_ENV=test" do
      allow(Rails.env).to receive(:test?).and_return(false)

      with_env("PHONE_CACHE_HMAC_SECRET_KEY" => "prod-hmac-secret") do
        expect(described_class.hmac_secret_key).to eq("prod-hmac-secret")
      end
    end
  end

  describe "missing PHONE_CACHE_HMAC_SECRET_KEY" do
    before do
      allow(described_class).to receive(:hmac_secret_key).and_return(nil)
    end

    it "raises an error naming the variable when hashing a present phone" do
      expect { described_class.digest("4105551234") }
        .to raise_error(PhoneCacheKey::MissingHmacSecretError, /PHONE_CACHE_HMAC_SECRET_KEY/)
    end

    it "still resolves a blank phone to the anonymous bucket without touching the secret" do
      expect(described_class.digest("")).to eq("anonymous")
    end
  end
end
