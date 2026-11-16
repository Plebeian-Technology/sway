# frozen_string_literal: true

require "rails_helper"

RSpec.describe SmsVerificationToken do
  include ActiveSupport::Testing::TimeHelpers

  let(:phone) { "4105550123" }

  include_context "with in-memory Rails.cache"

  describe ".issue!" do
    it "returns an opaque token string" do
      token = described_class.issue!(phone)
      expect(token).to be_a(String)
      expect(token.length).to be >= 32
    end

    it "stores the entry in Rails.cache with the phone bound" do
      token = described_class.issue!(phone)
      stored = Rails.cache.read("#{described_class::KEY_PREFIX}:#{token}")
      expect(stored).to be_present
      expect(stored[:phone]).to eq(PhoneCacheKey.digest(phone))
    end

    it "never stores the phone number itself" do
      token = described_class.issue!(phone)
      stored = Rails.cache.read("#{described_class::KEY_PREFIX}:#{token}")
      expect(stored[:phone]).not_to eq(phone.to_s)
    end
  end

  describe ".consume!" do
    it "returns true the first time when phone matches" do
      token = described_class.issue!(phone)
      expect(described_class.consume!(token, phone: phone)).to be(true)
    end

    it "returns false the second time (one-time-use)" do
      token = described_class.issue!(phone)
      described_class.consume!(token, phone: phone)
      expect(described_class.consume!(token, phone: phone)).to be(false)
    end

    it "returns false when phone does not match" do
      token = described_class.issue!(phone)
      expect(described_class.consume!(token, phone: "+19999999999")).to be(false)
    end

    it "returns false for the caller that loses the delete race" do
      token = described_class.issue!(phone)
      # Imitates the caller that loses a race: its read finds the entry, but
      # the delete that removed it came from the other request, so this delete
      # returns false — the token can only be spent once.
      allow(Rails.cache).to receive(:delete).and_return(false)
      expect(described_class.consume!(token, phone: phone)).to be(false)
    end

    it "returns false once ten minutes have passed since the token was issued" do
      token = described_class.issue!(phone)

      travel 11.minutes

      expect(described_class.peek(token)).to be_nil
      expect(described_class.consume!(token, phone: phone)).to be(false)
    end

    it "returns true when the token is used just before ten minutes have passed" do
      token = described_class.issue!(phone)

      travel 9.minutes

      expect(described_class.consume!(token, phone: phone)).to be(true)
    end

    it "returns false on nil token" do
      expect(described_class.consume!(nil, phone: phone)).to be(false)
    end

    it "returns false on blank token" do
      expect(described_class.consume!("", phone: phone)).to be(false)
    end

    it "returns false when cached phone digest is blank or malformed length" do
      token_blank = "token-blank"
      Rails.cache.write("#{described_class::KEY_PREFIX}:#{token_blank}", {phone: ""})
      expect(described_class.consume!(token_blank, phone: phone)).to be(false)

      token_short = "token-short"
      Rails.cache.write("#{described_class::KEY_PREFIX}:#{token_short}", {phone: "short"})
      expect(described_class.consume!(token_short, phone: phone)).to be(false)
    end
  end

  describe ".peek" do
    it "returns the stored payload WITHOUT consuming the token" do
      token = described_class.issue!(phone)

      peeked = described_class.peek(token)
      expect(peeked[:phone]).to eq(PhoneCacheKey.digest(phone))

      # A peek does not spend the token: it can still be used afterwards.
      expect(described_class.consume!(token, phone: phone)).to be(true)
    end

    it "returns nil for a blank, nil, or unknown token" do
      expect(described_class.peek("")).to be_nil
      expect(described_class.peek(nil)).to be_nil
      expect(described_class.peek("nonexistent-token")).to be_nil
    end
  end
end
