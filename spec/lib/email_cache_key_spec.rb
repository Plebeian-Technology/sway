# frozen_string_literal: true

require "rails_helper"

RSpec.describe EmailCacheKey do
  describe ".digest" do
    it "returns the same 128-char hex digest for case and whitespace variations of the same email" do
      digest = described_class.digest("User@Example.com")
      expect(digest).to match(/\A[0-9a-f]{128}\z/)
      expect(described_class.digest("  user@example.com \n")).to eq(digest)
    end

    it "returns different digests for different email addresses" do
      expect(described_class.digest("alice@example.com")).not_to eq(described_class.digest("bob@example.com"))
    end

    it "never returns the email address itself" do
      expect(described_class.digest("user@example.com")).not_to include("user@example.com")
    end

    it "returns the anonymous bucket for a blank email" do
      expect(described_class.digest("")).to eq("anonymous")
      expect(described_class.digest("   ")).to eq("anonymous")
      expect(described_class.digest(nil)).to eq("anonymous")
    end
  end

  describe "missing PHONE_CACHE_HMAC_SECRET_KEY" do
    before do
      allow(described_class).to receive(:hmac_secret_key).and_return(nil)
    end

    it "raises an error naming the variable when hashing a present email" do
      expect { described_class.digest("user@example.com") }
        .to raise_error(EmailCacheKey::MissingHmacSecretError, /PHONE_CACHE_HMAC_SECRET_KEY/)
    end

    it "still resolves a blank email to the anonymous bucket without touching the secret" do
      expect(described_class.digest("")).to eq("anonymous")
    end
  end
end
