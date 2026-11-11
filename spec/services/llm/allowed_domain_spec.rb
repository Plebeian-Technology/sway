# frozen_string_literal: true

require "rails_helper"

RSpec.describe Llm::AllowedDomain do
  describe ".from_url" do
    it "normalizes an https URL by stripping www and trailing slashes" do
      expect(described_class.from_url("https://www.thebanner.com/baltimore/")).to eq("thebanner.com/baltimore")
    end

    it "strips root path and leaves bare domain" do
      expect(described_class.from_url("https://apnews.com/")).to eq("apnews.com")
      expect(described_class.from_url("https://thehill.com")).to eq("thehill.com")
    end

    it "preserves subdomains other than www" do
      expect(described_class.from_url("https://baltimore.cbslocal.com/news/")).to eq("baltimore.cbslocal.com/news")
    end

    it "rejects non-https URLs" do
      expect(described_class.from_url("http://example.com/")).to be_nil
      expect(described_class.from_url("ftp://example.com/")).to be_nil
    end

    it "rejects IP addresses" do
      expect(described_class.from_url("https://192.168.1.1/news")).to be_nil
      expect(described_class.from_url("https://127.0.0.1/")).to be_nil
      expect(described_class.from_url("https://[::1]/")).to be_nil
    end

    it "rejects localhost and .localhost" do
      expect(described_class.from_url("https://localhost/news")).to be_nil
      expect(described_class.from_url("https://dev.localhost/news")).to be_nil
    end

    it "rejects bare TLDs and single-label hosts" do
      expect(described_class.from_url("https://com/")).to be_nil
      expect(described_class.from_url("https://internal/")).to be_nil
    end

    it "returns nil on blank or non-string inputs" do
      expect(described_class.from_url(nil)).to be_nil
      expect(described_class.from_url("")).to be_nil
      expect(described_class.from_url("   ")).to be_nil
      expect(described_class.from_url(123)).to be_nil
    end

    it "returns nil on malformed or unparseable URLs without raising" do
      expect(described_class.from_url("not a valid uri :::")).to be_nil
      expect(described_class.from_url("https://")).to be_nil
    end

    it "strips ports, userinfo, query parameters, and fragments while rejecting invalid label boundaries and handling IDNs" do
      expect(described_class.from_url("https://thebanner.com:8443/baltimore/")).to eq("thebanner.com/baltimore")
      expect(described_class.from_url("https://user:pass@thebanner.com/news/")).to eq("thebanner.com/news")
      expect(described_class.from_url("https://thebanner.com/news?category=politics#top")).to eq("thebanner.com/news")
      expect(described_class.from_url("https://xn--mnchen-3ya.de/news/")).to eq("xn--mnchen-3ya.de/news")
      expect(described_class.from_url("https://münchen.de/news")).to be_nil
      expect(described_class.from_url("https://-thebanner.com/")).to be_nil
      expect(described_class.from_url("https://thebanner-.com/")).to be_nil
      expect(described_class.from_url("https://thebanner..com/")).to be_nil
    end
  end

  describe ".filter_list" do
    it "filters, normalizes, and deduplicates URLs" do
      urls = [
        "https://www.thebanner.com/baltimore/",
        "https://thebanner.com/baltimore",
        "http://insecure.com",
        "https://www.wypr.org/",
        "invalid url"
      ]

      result = described_class.filter_list(urls)
      expect(result).to eq(["thebanner.com/baltimore", "wypr.org"])
    end

    it "returns an empty array when given nil or empty array" do
      expect(described_class.filter_list(nil)).to eq([])
      expect(described_class.filter_list([])).to eq([])
    end

    it "truncates lists exceeding 64 items and logs a warning" do
      urls = (1..70).map { |n| "https://news#{n}.example.com/path" }

      expect(SwayLogging).to receive(:warn).with(
        "llm.allowed_domains.truncated",
        max_domains: 64,
        received: 70,
        message: a_string_including("truncated to first 64")
      )

      result = described_class.filter_list(urls)
      expect(result.length).to eq(64)
      expect(result.first).to eq("news1.example.com/path")
      expect(result.last).to eq("news64.example.com/path")
    end

    it "filters out invalid entries before applying the 64-domain limit" do
      valid_urls = (1..60).map { |i| "https://news#{i}.maryland.gov/path" }
      invalid_urls = (1..20).map { |i| "http://insecure#{i}.example.com" }

      expect(SwayLogging).not_to receive(:warn)
      result = described_class.filter_list(valid_urls + invalid_urls)
      expect(result.length).to eq(60)
    end
  end
end
