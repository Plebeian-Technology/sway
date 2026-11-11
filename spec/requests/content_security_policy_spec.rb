# frozen_string_literal: true

require "rails_helper"

# @lat: [[csp-nonce-hardening#Why the CSP nonce generator switched to SecureRandom]]
#
# Each example sets itself up inline — no `let`, no helper `def` — so the type
# checker stays happy.
RSpec.describe "ContentSecurityPolicy", type: :request do
  # CSP_ENFORCE decides at boot which of the two header names carries the policy.
  describe "nonce generator" do
    it "does not derive the nonce from the client-supplied X-Request-Id" do
      request_id = "sway-csp-enum-0123456789abcdef"

      get "/", headers: {"X-Request-Id" => request_id}

      csp_header = response.headers["Content-Security-Policy"].to_s.presence ||
        response.headers["Content-Security-Policy-Report-Only"].to_s
      expect(csp_header).to include("'nonce-")
      # Under the old request.uuid generator the nonce WAS the cleaned-up
      # request id, so the header repeated it word for word. SecureRandom keeps
      # it out.
      expect(csp_header).not_to include(request_id)
    end

    it "produces a different nonce on each request" do
      get "/"
      header1 = response.headers["Content-Security-Policy"].to_s.presence ||
        response.headers["Content-Security-Policy-Report-Only"].to_s
      nonce1 = header1[/'nonce-([^']+)'/, 1]

      get "/"
      header2 = response.headers["Content-Security-Policy"].to_s.presence ||
        response.headers["Content-Security-Policy-Report-Only"].to_s
      nonce2 = header2[/'nonce-([^']+)'/, 1]

      expect(nonce1).to be_present
      expect(nonce2).to be_present
      expect(nonce1).not_to eq(nonce2)
    end
  end

  # @lat: [[content-security-policy#The CSP_ENFORCE staging switch]]
  describe "CSP_ENFORCE staging switch" do
    it "reads report_only from CSP_ENFORCE at boot" do
      expect(Rails.application.config.content_security_policy_report_only).to eq(ENV["CSP_ENFORCE"].blank?)
    end

    it "ships the policy under exactly one of the two header names" do
      get "/"

      if Rails.application.config.content_security_policy_report_only
        expect(response.headers["Content-Security-Policy-Report-Only"]).to be_present
        expect(response.headers["Content-Security-Policy"]).to be_blank
      else
        expect(response.headers["Content-Security-Policy"]).to be_present
        expect(response.headers["Content-Security-Policy-Report-Only"]).to be_blank
      end
    end

    it "keeps the report-uri directive in whichever mode booted" do
      get "/"

      csp_header = response.headers["Content-Security-Policy"].to_s.presence ||
        response.headers["Content-Security-Policy-Report-Only"].to_s
      expect(csp_header).to include("report-uri /csp-report")
    end

    it "allows connect-src to Nominatim and Google Maps" do
      get "/"

      csp_header = response.headers["Content-Security-Policy"].to_s.presence ||
        response.headers["Content-Security-Policy-Report-Only"].to_s
      expect(csp_header).to include("https://nominatim.openstreetmap.org")
      expect(csp_header).to include("https://maps.googleapis.com")
    end

    it "pins script-src to exact Google Maps and Cloudflare hosts without *.googleapis.com or *.cloudflare.com wildcards" do
      get "/"

      csp_header = response.headers["Content-Security-Policy"].to_s.presence ||
        response.headers["Content-Security-Policy-Report-Only"].to_s
      script_src = csp_header[/script-src ([^;]+)/, 1].to_s

      expect(script_src).to include("https://maps.googleapis.com")
      expect(script_src).to include("https://challenges.cloudflare.com")
      expect(script_src).to include("https://static.cloudflareinsights.com")
      expect(script_src).not_to include("https://*.googleapis.com")
      expect(script_src).not_to include("https://*.cloudflare.com")
    end
  end
end
