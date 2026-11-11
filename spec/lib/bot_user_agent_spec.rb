# frozen_string_literal: true

require "rails_helper"

RSpec.describe BotUserAgent do
  describe ".bot?" do
    it "classifies nil or blank user agents as bot" do
      expect(described_class.bot?(nil)).to be true
      expect(described_class.bot?("")).to be true
      expect(described_class.bot?("   ")).to be true
    end

    it "identifies search crawlers and scrapers" do
      expect(described_class.bot?("Mozilla/5.0 (compatible; Googlebot/2.1; +http://www.google.com/bot.html)")).to be true
      expect(described_class.bot?("Mozilla/5.0 (compatible; bingbot/2.0; +http://www.bing.com/bingbot.htm)")).to be true
      expect(described_class.bot?("Twitterbot/1.0")).to be true
      expect(described_class.bot?("facebookexternalhit/1.1 (+http://www.facebook.com/externalhit_uatext.php)")).to be true
      expect(described_class.bot?("Scrapy/2.11.0 (+https://scrapy.org)")).to be true
    end

    it "identifies automated HTTP clients and scripts" do
      expect(described_class.bot?("curl/8.4.0")).to be true
      expect(described_class.bot?("Wget/1.21.4")).to be true
      expect(described_class.bot?("python-requests/2.31.0")).to be true
      expect(described_class.bot?("Go-http-client/1.1")).to be true
      expect(described_class.bot?("PostmanRuntime/7.36.0")).to be true
      expect(described_class.bot?("node-fetch/1.0")).to be true
      expect(described_class.bot?("axios/1.6.2")).to be true
    end

    it "identifies headless browser automation runners" do
      expect(described_class.bot?("Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) HeadlessChrome/120.0.6099.109 Safari/537.36")).to be true
      expect(described_class.bot?("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Playwright/1.40.0 Safari/537.36")).to be true
      expect(described_class.bot?("Puppeteer")).to be true
      expect(described_class.bot?("Selenium/4.16.0 (Java)")).to be true
    end

    it "identifies genuine browser user agents as non-bot" do
      safari_ios = "Mozilla/5.0 (iPhone; CPU iPhone OS 17_1 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.1 Mobile/15E148 Safari/604.1"
      chrome_mac = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"
      firefox_win = "Mozilla/5.0 (Windows NT 10.0; Win64; x64; rv:121.0) Gecko/20100101 Firefox/121.0"

      expect(described_class.bot?(safari_ios)).to be false
      expect(described_class.bot?(chrome_mac)).to be false
      expect(described_class.bot?(firefox_win)).to be false
    end

    it "handles malformed or invalid byte sequences without raising errors" do
      invalid_ua = "Mozilla/5.0 \x80\x81".b
      expect { described_class.bot?(invalid_ua) }.not_to raise_error
    end
  end
end
