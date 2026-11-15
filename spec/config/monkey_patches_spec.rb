# frozen_string_literal: true

require "rails_helper"

RSpec.describe "String monkey patches" do
  describe "#normalize_phone" do
    it "returns 10 digits for a bare 10-digit input" do
      expect("4105551234".normalize_phone).to eq("4105551234")
    end

    it "strips common formatting characters" do
      expect("(410) 555-1234".normalize_phone).to eq("4105551234")
      expect("410.555.1234".normalize_phone).to eq("4105551234")
      expect("410 555 1234".normalize_phone).to eq("4105551234")
    end

    it "drops a leading 1 country code when input is 11 digits" do
      expect("14105551234".normalize_phone).to eq("4105551234")
      expect("+1 (410) 555-1234".normalize_phone).to eq("4105551234")
    end

    it "trims surrounding whitespace and newlines" do
      expect("  4105551234\n".normalize_phone).to eq("4105551234")
    end

    it "returns an empty string when no digits are present" do
      expect("".normalize_phone).to eq("")
      expect("no digits".normalize_phone).to eq("")
    end

    it "returns the digits-only string for lengths other than 10 or 11" do
      expect("555".normalize_phone).to eq("555")
      expect("123456789012".normalize_phone).to eq("123456789012")
    end

    it "does not strip a leading 1 from a valid 10-digit number" do
      expect("1234567890".normalize_phone).to eq("1234567890")
    end
  end

  describe "#possible_us_phone?" do
    it "is true for ten digits whose area code and exchange start with 2 to 9" do
      expect("4105551212".possible_us_phone?).to be(true)
    end

    it "is false when the area code or the exchange starts with 0 or 1, or the length is not ten digits" do
      expect(%w[1234567890 0105551212 4101551212 41055512].map(&:possible_us_phone?)).to all(be(false))
    end
  end
end
