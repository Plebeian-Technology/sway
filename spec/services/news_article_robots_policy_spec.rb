# frozen_string_literal: true

require "rails_helper"

RSpec.describe NewsArticleRobotsPolicy do
  include ActiveSupport::Testing::TimeHelpers

  # @lat: [[news-text#Robots exclusion policy enforcement]]
  let(:host) { "thebanner.com" }
  let(:base_url) { "https://#{host}" }
  let(:origin) { "#{base_url}:443" }

  before do
    described_class.reset_cache!
  end

  describe "Dimension 1: User-agent matching & group precedence (RFC 9309 §2.2.1)" do
    it "matches User-agent: SwayCivic case-insensitively" do
      robots_txt = <<~ROBOTS
        User-agent: swaycivic
        Disallow: /politics/
      ROBOTS
      stub_request(:get, "#{base_url}/robots.txt").to_return(status: 200, body: robots_txt)

      verdict = described_class.check(URI.parse("#{base_url}/politics/story-1"))
      expect(verdict.allowed?).to be false
      expect(verdict.reason).to eq(:robots_disallowed)
    end

    it "falls back to User-agent: * when no SwayCivic group is present" do
      robots_txt = <<~ROBOTS
        User-agent: Googlebot
        Disallow: /search

        User-agent: *
        Disallow: /politics/
      ROBOTS
      stub_request(:get, "#{base_url}/robots.txt").to_return(status: 200, body: robots_txt)

      verdict = described_class.check(URI.parse("#{base_url}/politics/story-1"))
      expect(verdict.allowed?).to be false
      expect(verdict.reason).to eq(:robots_disallowed)
    end

    it "applies specific SwayCivic group exclusively without falling back or merging with *" do
      robots_txt = <<~ROBOTS
        User-agent: *
        Disallow: /politics/

        User-agent: SwayCivic
        Allow: /politics/
        Disallow: /admin/
      ROBOTS
      stub_request(:get, "#{base_url}/robots.txt").to_return(status: 200, body: robots_txt)

      verdict_politics = described_class.check(URI.parse("#{base_url}/politics/story-1"))
      expect(verdict_politics.allowed?).to be true

      verdict_admin = described_class.check(URI.parse("#{base_url}/admin/dashboard"))
      expect(verdict_admin.allowed?).to be false
      expect(verdict_admin.reason).to eq(:robots_disallowed)
    end

    it "merges rules when multiple User-agent: SwayCivic groups exist across the file" do
      robots_txt = <<~ROBOTS
        User-agent: SwayCivic
        Disallow: /admin/

        User-agent: Googlebot
        Disallow: /search

        User-agent: SwayCivic
        Disallow: /internal/
      ROBOTS
      stub_request(:get, "#{base_url}/robots.txt").to_return(status: 200, body: robots_txt)

      expect(described_class.check(URI.parse("#{base_url}/admin/dash")).allowed?).to be false
      expect(described_class.check(URI.parse("#{base_url}/internal/secret")).allowed?).to be false
      expect(described_class.check(URI.parse("#{base_url}/politics/story")).allowed?).to be true
    end

    it "allows all paths when robots.txt contains only other user-agents and no *" do
      robots_txt = <<~ROBOTS
        User-agent: Googlebot
        Disallow: /

        User-agent: Bingbot
        Disallow: /
      ROBOTS
      stub_request(:get, "#{base_url}/robots.txt").to_return(status: 200, body: robots_txt)

      verdict = described_class.check(URI.parse("#{base_url}/politics/story-1"))
      expect(verdict.allowed?).to be true
    end

    it "retains group boundaries and does not fold subsequent agent rules when empty Disallow occurs" do
      robots_txt = <<~ROBOTS
        User-agent: SwayCivic
        Disallow:

        User-agent: OtherBot
        Allow: /private/

        User-agent: SwayCivic
        Disallow: /private/
      ROBOTS
      stub_request(:get, "#{base_url}/robots.txt").to_return(status: 200, body: robots_txt)

      verdict = described_class.check(URI.parse("#{base_url}/private/story"))
      expect(verdict.allowed?).to be false
      expect(verdict.reason).to eq(:robots_disallowed)
    end
  end

  describe "Dimension 2: Longest-match & Allow/Disallow precedence (RFC 9309 §2.2.2)" do
    it "gives precedence to longer Allow rule over shorter Disallow rule" do
      robots_txt = <<~ROBOTS
        User-agent: *
        Disallow: /politics/
        Allow: /politics/council-housing/
      ROBOTS
      stub_request(:get, "#{base_url}/robots.txt").to_return(status: 200, body: robots_txt)

      allowed_url = "#{base_url}/politics/council-housing/bill-24-0012"
      disallowed_url = "#{base_url}/politics/budget/bill-24-0013"

      expect(described_class.check(URI.parse(allowed_url)).allowed?).to be true
      expect(described_class.check(URI.parse(disallowed_url)).allowed?).to be false
    end

    it "gives precedence to longer Disallow rule over shorter Allow rule" do
      robots_txt = <<~ROBOTS
        User-agent: *
        Allow: /politics/
        Disallow: /politics/confidential/
      ROBOTS
      stub_request(:get, "#{base_url}/robots.txt").to_return(status: 200, body: robots_txt)

      expect(described_class.check(URI.parse("#{base_url}/politics/open-meeting")).allowed?).to be true
      expect(described_class.check(URI.parse("#{base_url}/politics/confidential/memo")).allowed?).to be false
    end

    it "resolves equal-length Allow and Disallow in favor of Allow (tie-breaker)" do
      robots_txt = <<~ROBOTS
        User-agent: *
        Disallow: /politics/item
        Allow: /politics/item
      ROBOTS
      stub_request(:get, "#{base_url}/robots.txt").to_return(status: 200, body: robots_txt)

      expect(described_class.check(URI.parse("#{base_url}/politics/item")).allowed?).to be true
    end

    it "supports wildcards (*) in rule paths" do
      robots_txt = <<~ROBOTS
        User-agent: *
        Disallow: /politics/*.pdf
        Allow: /politics/*
      ROBOTS
      stub_request(:get, "#{base_url}/robots.txt").to_return(status: 200, body: robots_txt)

      expect(described_class.check(URI.parse("#{base_url}/politics/report.html")).allowed?).to be true
      expect(described_class.check(URI.parse("#{base_url}/politics/report.pdf")).allowed?).to be false
    end

    it "supports end-of-path anchor ($) in rule paths" do
      robots_txt = <<~ROBOTS
        User-agent: *
        Disallow: /politics$
      ROBOTS
      stub_request(:get, "#{base_url}/robots.txt").to_return(status: 200, body: robots_txt)

      expect(described_class.check(URI.parse("#{base_url}/politics")).allowed?).to be false
      expect(described_class.check(URI.parse("#{base_url}/politics/story")).allowed?).to be true
    end

    it "treats empty Disallow: as allow all" do
      robots_txt = <<~ROBOTS
        User-agent: *
        Disallow:
      ROBOTS
      stub_request(:get, "#{base_url}/robots.txt").to_return(status: 200, body: robots_txt)

      expect(described_class.check(URI.parse("#{base_url}/any/path")).allowed?).to be true
    end

    it "normalizes unreserved percent-encoding in matching path" do
      robots_txt = <<~ROBOTS
        User-agent: *
        Disallow: /foo/bar/baz
      ROBOTS
      stub_request(:get, "#{base_url}/robots.txt").to_return(status: 200, body: robots_txt)

      expect(described_class.check(URI.parse("#{base_url}/foo/bar/%62%61%7A")).allowed?).to be false
    end

    it "refuses crawl when robots.txt contains literal UTF-8 rule matching percent-encoded URL" do
      robots_txt = <<~ROBOTS
        User-agent: *
        Disallow: /café/
      ROBOTS
      stub_request(:get, "#{base_url}/robots.txt").to_return(status: 200, body: robots_txt)

      verdict = described_class.check(URI.parse("#{base_url}/caf%C3%A9/story"))
      expect(verdict.allowed?).to be false
      expect(verdict.reason).to eq(:robots_disallowed)
    end

    it "refuses crawl when robots.txt contains lowercase percent-encoded rule matching uppercase percent-encoded URL" do
      robots_txt = <<~ROBOTS
        User-agent: *
        Disallow: /caf%c3%a9/
      ROBOTS
      stub_request(:get, "#{base_url}/robots.txt").to_return(status: 200, body: robots_txt)

      verdict = described_class.check(URI.parse("#{base_url}/caf%C3%A9/story"))
      expect(verdict.allowed?).to be false
      expect(verdict.reason).to eq(:robots_disallowed)
    end

    it "computes consistent specificity length between literal UTF-8 and percent-encoded rules" do
      robots_txt = <<~ROBOTS
        User-agent: *
        Disallow: /café/
        Allow: /caf%C3%A9/
      ROBOTS
      stub_request(:get, "#{base_url}/robots.txt").to_return(status: 200, body: robots_txt)

      # Equal length in normalized octets (11 bytes) -> Allow tie-breaker wins per RFC 9309 §2.2.2
      verdict = described_class.check(URI.parse("#{base_url}/caf%C3%A9/story"))
      expect(verdict.allowed?).to be true
    end

    it "implicitly allows /robots.txt even when root is disallowed" do
      robots_txt = <<~ROBOTS
        User-agent: *
        Disallow: /
      ROBOTS
      stub_request(:get, "#{base_url}/robots.txt").to_return(status: 200, body: robots_txt)

      expect(described_class.check(URI.parse("#{base_url}/robots.txt")).allowed?).to be true
    end
  end

  describe "Dimension 3: HTTP status codes & accessibility (RFC 9309 §2.3.1)" do
    it "allows retrieval on HTTP 404 Not Found" do
      stub_request(:get, "#{base_url}/robots.txt").to_return(status: 404, body: "Not Found")
      expect(described_class.check(URI.parse("#{base_url}/politics/story")).allowed?).to be true
    end

    it "allows retrieval on HTTP 410 Gone" do
      stub_request(:get, "#{base_url}/robots.txt").to_return(status: 410, body: "Gone")
      expect(described_class.check(URI.parse("#{base_url}/politics/story")).allowed?).to be true
    end

    it "fails closed (disallows) on HTTP 500/502/503 server errors" do
      [500, 502, 503].each do |status_code|
        described_class.reset_cache!
        stub_request(:get, "#{base_url}/robots.txt").to_return(status: status_code, body: "Server Error")

        verdict = described_class.check(URI.parse("#{base_url}/politics/story"))
        expect(verdict.allowed?).to be false
        expect(verdict.reason).to eq(:robots_server_error)
      end
    end

    it "fails closed on network timeout or connection refused" do
      stub_request(:get, "#{base_url}/robots.txt").to_timeout

      verdict = described_class.check(URI.parse("#{base_url}/politics/story"))
      expect(verdict.allowed?).to be false
      expect(verdict.reason).to eq(:robots_inaccessible)
    end

    it "fails closed on HTTP 401, 403, and 429" do
      [401, 403, 429].each do |status_code|
        described_class.reset_cache!
        stub_request(:get, "#{base_url}/robots.txt").to_return(status: status_code, body: "Restricted")

        verdict = described_class.check(URI.parse("#{base_url}/politics/story"))
        expect(verdict.allowed?).to be false
        expect(verdict.reason).to eq(:robots_inaccessible)
      end
    end

    it "fails closed on challenge screens returning HTTP 200 for robots.txt" do
      challenge_html = <<~HTML
        <html><head><title>Just a moment...</title></head><body><div id="cf-challenge-running"></div></body></html>
      HTML
      stub_request(:get, "#{base_url}/robots.txt").to_return(status: 200, body: challenge_html, headers: {"Content-Type" => "text/html"})

      verdict = described_class.check(URI.parse("#{base_url}/politics/story"))
      expect(verdict.allowed?).to be false
      expect(verdict.reason).to eq(:robots_challenged)
    end

    it "fails closed on HTTP 200 text/html response with account or subscription markup and does not cache an allow policy" do
      html_subscription = <<~HTML
        <!DOCTYPE html>
        <html>
          <head><title>Account</title></head>
          <body>
            <h1>Subscribe to continue</h1>
            <p>Please purchase a digital subscription to read further.</p>
          </body>
        </html>
      HTML
      stub_request(:get, "#{base_url}/robots.txt")
        .to_return(status: 200, headers: {"Content-Type" => "text/html"}, body: html_subscription)

      verdict = described_class.check(URI.parse("#{base_url}/politics/story"))
      expect(verdict.allowed?).to be false
      expect(verdict.reason).to eq(:robots_inaccessible)

      expect(described_class.instance_variable_get(:@cache)[origin]).to be_nil
    end

    it "fails closed on HTTP 200 response with Content-Type: text/html even without challenge markup" do
      stub_request(:get, "#{base_url}/robots.txt")
        .to_return(status: 200, headers: {"Content-Type" => "text/html"}, body: "<html><body><p>Hello world</p></body></html>")

      verdict = described_class.check(URI.parse("#{base_url}/politics/story"))
      expect(verdict.allowed?).to be false
      expect(verdict.reason).to eq(:robots_inaccessible)
      expect(described_class.instance_variable_get(:@cache)[origin]).to be_nil
    end

    it "fails closed on HTTP 200 response with HTML document markup in body even if Content-Type header is omitted" do
      html_body = "<!DOCTYPE html>\n<html><head><title>News Portal</title></head><body>Welcome</body></html>"
      stub_request(:get, "#{base_url}/robots.txt")
        .to_return(status: 200, body: html_body)

      verdict = described_class.check(URI.parse("#{base_url}/politics/story"))
      expect(verdict.allowed?).to be false
      expect(verdict.reason).to eq(:robots_inaccessible)
      expect(described_class.instance_variable_get(:@cache)[origin]).to be_nil
    end

    it "re-raises WebMock::NetConnectNotAllowedError visibly without converting to absent allow policy" do
      req_sig_class = Object.const_get("WebMock::RequestSignature")
      net_error_class = Object.const_get("WebMock::NetConnectNotAllowedError")
      req_sig = req_sig_class.new(:get, "#{base_url}/robots.txt")
      stub_request(:get, "#{base_url}/robots.txt")
        .to_raise(net_error_class.new(req_sig))

      expect {
        described_class.check(URI.parse("#{base_url}/politics/story"))
      }.to raise_error(net_error_class)
    end

    it "re-raises VCR::Errors::UnhandledHTTPRequestError visibly without converting to absent allow policy" do
      vcr_error_class = Object.const_get("VCR::Errors::UnhandledHTTPRequestError")
      vcr_req = VCR::Request.new(:get, "#{base_url}/robots.txt")
      stub_request(:get, "#{base_url}/robots.txt")
        .to_raise(vcr_error_class.new(vcr_req))

      expect {
        described_class.check(URI.parse("#{base_url}/politics/story"))
      }.to raise_error(vcr_error_class)
    end

    it "allows crawling on valid empty text/plain policy and caches policy" do
      stub_request(:get, "#{base_url}/robots.txt")
        .to_return(status: 200, headers: {"Content-Type" => "text/plain"}, body: "")

      verdict = described_class.check(URI.parse("#{base_url}/politics/story"))
      expect(verdict.allowed?).to be true
      expect(described_class.instance_variable_get(:@cache)[origin]).not_to be_nil
    end

    it "allows crawling on valid comment-only text/plain policy and caches policy" do
      stub_request(:get, "#{base_url}/robots.txt")
        .to_return(status: 200, headers: {"Content-Type" => "text/plain"}, body: "# Welcome all crawlers\n# No restrictions\n")

      verdict = described_class.check(URI.parse("#{base_url}/politics/story"))
      expect(verdict.allowed?).to be true
      expect(described_class.instance_variable_get(:@cache)[origin]).not_to be_nil
    end
  end

  describe "Dimension 4: Multi-hop redirects and SSRF guards on robots.txt" do
    it "follows 301/302 redirects to safe destinations for robots.txt" do
      stub_request(:get, "#{base_url}/robots.txt")
        .to_return(status: 301, headers: {"Location" => "https://www.#{host}/robots.txt"})
      stub_request(:get, "https://www.#{host}/robots.txt")
        .to_return(status: 200, body: "User-agent: *\nDisallow: /secret/\n")

      expect(described_class.check(URI.parse("#{base_url}/politics/story")).allowed?).to be true
      expect(described_class.check(URI.parse("#{base_url}/secret/doc")).allowed?).to be false
    end

    it "fails closed when robots.txt redirects to a private IP (SSRF guard)" do
      stub_request(:get, "#{base_url}/robots.txt")
        .to_return(status: 302, headers: {"Location" => "http://169.254.169.254/robots.txt"})

      verdict = described_class.check(URI.parse("#{base_url}/politics/story"))
      expect(verdict.allowed?).to be false
      expect(verdict.reason).to eq(:robots_unsafe_destination)
      expect(WebMock).not_to have_requested(:any, /169\.254\./)
    end

    it "fails closed when robots.txt redirect chain exceeds 3 hops" do
      stub_request(:get, "#{base_url}/robots.txt").to_return(status: 302, headers: {"Location" => "#{base_url}/r1"})
      stub_request(:get, "#{base_url}/r1").to_return(status: 302, headers: {"Location" => "#{base_url}/r2"})
      stub_request(:get, "#{base_url}/r2").to_return(status: 302, headers: {"Location" => "#{base_url}/r3"})
      stub_request(:get, "#{base_url}/r3").to_return(status: 302, headers: {"Location" => "#{base_url}/r4"})

      verdict = described_class.check(URI.parse("#{base_url}/politics/story"))
      expect(verdict.allowed?).to be false
      expect(verdict.reason).to eq(:robots_redirect_limit_exceeded)
      expect(WebMock).not_to have_requested(:get, "#{base_url}/r4")
    end
  end

  describe "Dimension 5: Caching & bounded efficiency" do
    it "requests robots.txt at most once per host across multiple checks" do
      stub_request(:get, "#{base_url}/robots.txt")
        .to_return(status: 200, body: "User-agent: *\nDisallow: /admin/\n")

      described_class.check(URI.parse("#{base_url}/politics/story-1"))
      described_class.check(URI.parse("#{base_url}/politics/story-2"))
      described_class.check(URI.parse("#{base_url}/admin/settings"))

      expect(WebMock).to have_requested(:get, "#{base_url}/robots.txt").once
    end

    it "expires cache after bounded TTL" do
      stub_request(:get, "#{base_url}/robots.txt")
        .to_return(status: 200, body: "User-agent: *\nDisallow: /admin/\n")

      described_class.check(URI.parse("#{base_url}/politics/story-1"))
      expect(WebMock).to have_requested(:get, "#{base_url}/robots.txt").once

      travel_to(25.hours.from_now) do
        described_class.check(URI.parse("#{base_url}/politics/story-2"))
        expect(WebMock).to have_requested(:get, "#{base_url}/robots.txt").twice
      end
    end
  end

  describe "Dimension 6: RFC 9309 line endings and UTF-8 BOM normalization" do
    it "recognizes user-agent groups and disallow directives separated solely by carriage returns (CR-only)" do
      robots_txt = "User-agent: *\rDisallow: /politics/\r"
      stub_request(:get, "#{base_url}/robots.txt")
        .to_return(status: 200, headers: {"Content-Type" => "text/plain"}, body: robots_txt)

      verdict = described_class.check(URI.parse("#{base_url}/politics/housing"))
      expect(verdict.allowed?).to be false
      expect(verdict.reason).to eq(:robots_disallowed)
    end

    it "allows access when robots.txt uses CR-only (\r) line endings with an Allow directive" do
      robots_txt = "User-agent: *\rDisallow: /politics/\rAllow: /politics/allowed\r"
      stub_request(:get, "#{base_url}/robots.txt")
        .to_return(status: 200, headers: {"Content-Type" => "text/plain"}, body: robots_txt)

      verdict = described_class.check(URI.parse("#{base_url}/politics/allowed"))
      expect(verdict.allowed?).to be true
    end

    it "recognizes user-agent groups and disallow directives with CRLF and mixed line endings" do
      robots_txt = "User-agent: SwayCivic\r\nDisallow: /politics/\r\nUser-agent: *\rDisallow: /all/\n"
      stub_request(:get, "#{base_url}/robots.txt")
        .to_return(status: 200, headers: {"Content-Type" => "text/plain"}, body: robots_txt)

      expect(described_class.check(URI.parse("#{base_url}/politics/housing")).allowed?).to be false
      expect(described_class.check(URI.parse("#{base_url}/all/housing")).allowed?).to be true
    end

    it "recognizes user-agent groups and disallow directives prefixed with a UTF-8 BOM" do
      robots_txt = "\xEF\xBB\xBFUser-agent: *\nDisallow: /politics/\n"
      stub_request(:get, "#{base_url}/robots.txt")
        .to_return(status: 200, headers: {"Content-Type" => "text/plain"}, body: robots_txt)

      verdict = described_class.check(URI.parse("#{base_url}/politics/housing"))
      expect(verdict.allowed?).to be false
      expect(verdict.reason).to eq(:robots_disallowed)
    end

    it "allows crawling allowed paths when robots.txt contains a leading UTF-8 BOM" do
      robots_txt = "\uFEFFUser-agent: *\nDisallow: /politics/\nAllow: /politics/allowed\n"
      stub_request(:get, "#{base_url}/robots.txt")
        .to_return(status: 200, headers: {"Content-Type" => "text/plain"}, body: robots_txt)

      verdict = described_class.check(URI.parse("#{base_url}/politics/allowed"))
      expect(verdict.allowed?).to be true
    end

    it "maintains parity between BOM-prefixed and plain policies across Allow and Disallow decisions" do
      plain_txt = "User-agent: *\nDisallow: /politics/\nAllow: /politics/public\n"
      bom_txt = "\uFEFFUser-agent: *\nDisallow: /politics/\nAllow: /politics/public\n"

      stub_request(:get, "#{base_url}/robots.txt")
        .to_return(status: 200, headers: {"Content-Type" => "text/plain"}, body: plain_txt)
      expect(described_class.check(URI.parse("#{base_url}/politics/private")).allowed?).to be false
      expect(described_class.check(URI.parse("#{base_url}/politics/public")).allowed?).to be true

      described_class.reset_cache!
      stub_request(:get, "#{base_url}/robots.txt")
        .to_return(status: 200, headers: {"Content-Type" => "text/plain"}, body: bom_txt)
      expect(described_class.check(URI.parse("#{base_url}/politics/private")).allowed?).to be false
      expect(described_class.check(URI.parse("#{base_url}/politics/public")).allowed?).to be true
    end
  end

  describe "Dimension 7: Access barrier refusal on 404/410 and HTML login fragments" do
    it "fails closed with :robots_challenged on HTTP 404 response with CAPTCHA challenge markup and does not cache an allow policy" do
      captcha_html = '<html><title>Human Verification</title><body><div class="h-captcha" data-sitekey="test"></div></body></html>'
      stub_request(:get, "#{base_url}/robots.txt")
        .to_return(status: 404, headers: {"Content-Type" => "text/html"}, body: captcha_html)

      verdict = described_class.check(URI.parse("#{base_url}/politics/story"))
      expect(verdict.allowed?).to be false
      expect(verdict.reason).to eq(:robots_challenged)
      expect(described_class.instance_variable_get(:@cache)[origin]).to be_nil
    end

    it "fails closed with :robots_challenged on HTTP 410 response with CAPTCHA challenge markup and does not cache an allow policy" do
      captcha_html = '<!DOCTYPE html><html><head><title>Just a moment...</title></head><body><div id="cf-challenge-running"></div></body></html>'
      stub_request(:get, "#{base_url}/robots.txt")
        .to_return(status: 410, headers: {"Content-Type" => "text/html"}, body: captcha_html)

      verdict = described_class.check(URI.parse("#{base_url}/politics/story"))
      expect(verdict.allowed?).to be false
      expect(verdict.reason).to eq(:robots_challenged)
      expect(described_class.instance_variable_get(:@cache)[origin]).to be_nil
    end

    it "fails closed with :robots_inaccessible on HTTP 404 response with login barrier markup and does not cache an allow policy" do
      login_html = '<div><h1>Sign in</h1><form action="/login"><input type="password"><button>Sign in</button></form></div>'
      stub_request(:get, "#{base_url}/robots.txt")
        .to_return(status: 404, headers: {"Content-Type" => "text/html"}, body: login_html)

      verdict = described_class.check(URI.parse("#{base_url}/politics/story"))
      expect(verdict.allowed?).to be false
      expect(verdict.reason).to eq(:robots_inaccessible)
      expect(described_class.instance_variable_get(:@cache)[origin]).to be_nil
    end

    it "fails closed with :robots_inaccessible on HTTP 410 response with login barrier markup and does not cache an allow policy" do
      login_html = '<form action="/auth/login" method="post"><input type="password" name="password"><input type="submit" value="Log In"></form>'
      stub_request(:get, "#{base_url}/robots.txt")
        .to_return(status: 410, headers: {"Content-Type" => "text/html"}, body: login_html)

      verdict = described_class.check(URI.parse("#{base_url}/politics/story"))
      expect(verdict.allowed?).to be false
      expect(verdict.reason).to eq(:robots_inaccessible)
      expect(described_class.instance_variable_get(:@cache)[origin]).to be_nil
    end

    it "fails closed with :robots_inaccessible on HTTP 404 response with paywall barrier markup and does not cache an allow policy" do
      paywall_html = '<div class="paywall"><h2>Subscribe to continue</h2><p>This content is for subscribers only.</p></div>'
      stub_request(:get, "#{base_url}/robots.txt")
        .to_return(status: 404, headers: {"Content-Type" => "text/html"}, body: paywall_html)

      verdict = described_class.check(URI.parse("#{base_url}/politics/story"))
      expect(verdict.allowed?).to be false
      expect(verdict.reason).to eq(:robots_inaccessible)
      expect(described_class.instance_variable_get(:@cache)[origin]).to be_nil
    end

    it "fails closed with :robots_inaccessible on HTTP 410 response with paywall barrier markup and does not cache an allow policy" do
      paywall_html = '<aside class="subscription-gate"><h3>Subscription required</h3><p>Unlock this article with a subscription.</p></aside>'
      stub_request(:get, "#{base_url}/robots.txt")
        .to_return(status: 410, headers: {"Content-Type" => "text/html"}, body: paywall_html)

      verdict = described_class.check(URI.parse("#{base_url}/politics/story"))
      expect(verdict.allowed?).to be false
      expect(verdict.reason).to eq(:robots_inaccessible)
      expect(described_class.instance_variable_get(:@cache)[origin]).to be_nil
    end

    it "fails closed with :robots_inaccessible on HTTP 200 response with HTML login fragment served as text/plain and does not cache an allow policy" do
      login_fragment = '<div><h1>Sign in</h1><form action="/login"><input type="password"><button>Sign in</button></form></div>'
      stub_request(:get, "#{base_url}/robots.txt")
        .to_return(status: 200, headers: {"Content-Type" => "text/plain"}, body: login_fragment)

      verdict = described_class.check(URI.parse("#{base_url}/politics/story"))
      expect(verdict.allowed?).to be false
      expect(verdict.reason).to eq(:robots_inaccessible)
      expect(described_class.instance_variable_get(:@cache)[origin]).to be_nil
    end

    it "fails closed with :robots_inaccessible on HTTP 200 response with HTML login fragment when Content-Type is omitted and does not cache an allow policy" do
      login_fragment = '<div><h1>Sign in</h1><form action="/login"><input type="password"><button>Sign in</button></form></div>'
      stub_request(:get, "#{base_url}/robots.txt")
        .to_return(status: 200, body: login_fragment)

      verdict = described_class.check(URI.parse("#{base_url}/politics/story"))
      expect(verdict.allowed?).to be false
      expect(verdict.reason).to eq(:robots_inaccessible)
      expect(described_class.instance_variable_get(:@cache)[origin]).to be_nil
    end

    it "allows crawling and caches absent policy on genuine HTTP 404 with standard HTML not-found page without barrier evidence" do
      standard_404_html = <<~HTML
        <!DOCTYPE html>
        <html>
          <head><title>404 Not Found</title></head>
          <body>
            <h1>404 Not Found</h1>
            <p>The requested URL /robots.txt was not found on this server.</p>
          </body>
        </html>
      HTML
      stub_request(:get, "#{base_url}/robots.txt")
        .to_return(status: 404, headers: {"Content-Type" => "text/html; charset=utf-8"}, body: standard_404_html)

      verdict = described_class.check(URI.parse("#{base_url}/politics/story"))
      expect(verdict.allowed?).to be true
      cached = described_class.instance_variable_get(:@cache)[origin]
      expect(cached).not_to be_nil
      expect(cached.policy.absent).to be true
    end

    it "allows crawling and caches absent policy on genuine HTTP 410 with standard HTML gone page without barrier evidence" do
      standard_410_html = <<~HTML
        <!DOCTYPE html>
        <html>
          <head><title>410 Gone</title></head>
          <body>
            <h1>Resource Gone</h1>
            <p>The robots.txt file has been permanently removed.</p>
          </body>
        </html>
      HTML
      stub_request(:get, "#{base_url}/robots.txt")
        .to_return(status: 410, headers: {"Content-Type" => "text/html; charset=utf-8"}, body: standard_410_html)

      verdict = described_class.check(URI.parse("#{base_url}/politics/story"))
      expect(verdict.allowed?).to be true
      cached = described_class.instance_variable_get(:@cache)[origin]
      expect(cached).not_to be_nil
      expect(cached.policy.absent).to be true
    end

    it "does not reuse permissive cache after barrier refusal and re-queries endpoint on subsequent checks" do
      captcha_html = '<html><title>Human Verification</title><body><div class="h-captcha" data-sitekey="test"></div></body></html>'
      stub_request(:get, "#{base_url}/robots.txt")
        .to_return(status: 404, headers: {"Content-Type" => "text/html"}, body: captcha_html)

      verdict1 = described_class.check(URI.parse("#{base_url}/politics/story"))
      expect(verdict1.allowed?).to be false
      expect(described_class.instance_variable_get(:@cache)[origin]).to be_nil

      valid_robots = "User-agent: *\nAllow: /\n"
      stub_request(:get, "#{base_url}/robots.txt")
        .to_return(status: 200, headers: {"Content-Type" => "text/plain"}, body: valid_robots)

      verdict2 = described_class.check(URI.parse("#{base_url}/politics/story"))
      expect(verdict2.allowed?).to be true
      expect(described_class.instance_variable_get(:@cache)[origin]).not_to be_nil
      expect(WebMock).to have_requested(:get, "#{base_url}/robots.txt").twice
    end

    it "does not resurrect or reuse expired permissive cache when fresh fetch returns an access barrier" do
      include ActiveSupport::Testing::TimeHelpers

      stub_request(:get, "#{base_url}/robots.txt")
        .to_return(status: 200, headers: {"Content-Type" => "text/plain"}, body: "User-agent: *\nAllow: /\n")

      verdict1 = described_class.check(URI.parse("#{base_url}/politics/story"))
      expect(verdict1.allowed?).to be true

      travel 86_401.seconds do
        captcha_body = '<html><title>Human Verification</title><body><div class="h-captcha" data-sitekey="test"></div></body></html>'
        stub_request(:get, "#{base_url}/robots.txt")
          .to_return(status: 404, headers: {"Content-Type" => "text/html"}, body: captcha_body)

        verdict2 = described_class.check(URI.parse("#{base_url}/politics/story"))
        expect(verdict2.allowed?).to be false
        expect(verdict2.reason).to eq(:robots_challenged)
        expect(WebMock).to have_requested(:get, "#{base_url}/robots.txt").twice
      end
    end

    it "scrubs invalid UTF-8 byte sequences during parse_robots_txt without raising encoding errors" do
      robots_txt = "User-agent: *\n# Invalid byte: \xFF\xFE in comment\nDisallow: /politics/\n"
      groups = described_class.send(:parse_robots_txt, robots_txt)
      policy = described_class.new(origin: origin, groups: groups)

      verdict = policy.check_uri(URI.parse("#{base_url}/politics/story"))
      expect(verdict.allowed?).to be false
      expect(verdict.reason).to eq(:robots_disallowed)
    end

    it "matches SwayCivic when robots.txt specifies product version suffix (SwayCivic/2.0)" do
      robots_txt = "User-agent: SwayCivic/2.0\nDisallow: /politics/\n"
      stub_request(:get, "#{base_url}/robots.txt")
        .to_return(status: 200, headers: {"Content-Type" => "text/plain"}, body: robots_txt)

      verdict = described_class.check(URI.parse("#{base_url}/politics/story"))
      expect(verdict.allowed?).to be false
      expect(verdict.reason).to eq(:robots_disallowed)
    end

    it "calculates rule specificity by normalized octet bytesize per RFC 9309 §2.2.2" do
      robots_txt = <<~ROBOTS
        User-agent: *
        Disallow: /politics/
        Allow: /polit%C3%ADca/
      ROBOTS
      stub_request(:get, "#{base_url}/robots.txt")
        .to_return(status: 200, headers: {"Content-Type" => "text/plain"}, body: robots_txt)

      accented_target = URI.parse("#{base_url}/polit%C3%ADca/ley")
      expect(described_class.check(accented_target).allowed?).to be true
    end
  end
end
