# frozen_string_literal: true

require "rails_helper"

RSpec.describe "CspReports", type: :request do
  let(:valid_body) do
    {
      "csp-report" => {
        "blocked-uri" => "https://evil.example.com/x.js",
        "violated-directive" => "script-src",
        "document-uri" => "https://sway.vote/bills",
        "source-file" => "https://sway.vote/app.js"
      }
    }.to_json
  end

  describe "POST /csp-report" do
    it "returns 204 for application/csp-report content-type" do
      post "/csp-report", params: valid_body, headers: {"CONTENT_TYPE" => "application/csp-report"}
      expect(response).to have_http_status(:no_content)
    end

    it "returns 204 for application/reports+json content-type" do
      post "/csp-report", params: valid_body, headers: {"CONTENT_TYPE" => "application/reports+json"}
      expect(response).to have_http_status(:no_content)
    end

    # @lat: [[csp-reports-firefox-array-format#Why the CSP reports endpoint handles two body shapes]]
    it "handles Firefox reports+json Array body without 500 and extracts camelCase fields" do
      firefox_body = [
        {
          "age" => 1000,
          "type" => "csp-violation",
          "url" => "https://sway.vote/bills",
          "user_agent" => "Mozilla/5.0 Firefox/149.0",
          "body" => {
            "blockedURL" => "https://evil.example.com/x.js",
            "effectiveDirective" => "script-src-elem",
            "violatedDirective" => "script-src-elem",
            "documentURL" => "https://sway.vote/bills",
            "sourceFile" => "https://sway.vote/app.js"
          }
        }
      ].to_json

      expect(SwayLogging).to receive(:warn).with(
        "csp.violation",
        hash_including(
          blocked_uri: "https://evil.example.com/x.js",
          violated_directive: "script-src-elem",
          document_uri: "https://sway.vote/bills",
          source_file: "https://sway.vote/app.js"
        )
      )
      post "/csp-report", params: firefox_body, headers: {"CONTENT_TYPE" => "application/reports+json"}
      expect(response).to have_http_status(:no_content)
    end

    it "returns 415 for application/json content-type" do
      post "/csp-report", params: valid_body, headers: {"CONTENT_TYPE" => "application/json"}
      expect(response).to have_http_status(:unsupported_media_type)
    end

    it "returns 413 when Content-Length > 1 MB" do
      huge = "x" * (1.megabyte + 1)
      post "/csp-report", params: huge,
        headers: {
          "CONTENT_TYPE" => "application/csp-report",
          "CONTENT_LENGTH" => (1.megabyte + 1).to_s
        }
      expect(response).to have_http_status(:content_too_large)
    end

    it "returns 413 when body exceeds 1 MB even with Content-Length omitted" do
      huge = "x" * (CspReportsController::MAX_BODY_BYTES + 1)
      expect(JSON).not_to receive(:parse)
      post "/csp-report", params: huge,
        headers: {
          "CONTENT_TYPE" => "application/csp-report",
          "CONTENT_LENGTH" => nil,
          "HTTP_TRANSFER_ENCODING" => "chunked"
        }
      expect(response).to have_http_status(:content_too_large)
    end

    it "swallows JSON parse errors and still returns 204" do
      post "/csp-report", params: "not-json-at-all", headers: {"CONTENT_TYPE" => "application/csp-report"}
      expect(response).to have_http_status(:no_content)
    end

    it "logs via SwayLogging.warn with structured fields" do
      expect(SwayLogging).to receive(:warn).with("csp.violation", hash_including(:blocked_uri, :violated_directive))
      post "/csp-report", params: valid_body, headers: {"CONTENT_TYPE" => "application/csp-report"}
    end

    # Browser extensions inject scripts the page never wrote. In the older
    # report format source-file is often just the scheme name
    # ("moz-extension"), while modern browsers send the full URI. Both shapes
    # have to be recognized.
    %w[
      moz-extension
      moz-extension://abcd-1234/inject.js
      chrome-extension://aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/content.js
      safari-web-extension://1234/script.js
      webkit-masked-url://hidden/
    ].each do |ext_uri|
      it "drops extension violation from #{ext_uri.split("/").first} without logging" do
        body = {
          "csp-report" => {
            "blocked-uri" => "inline",
            "violated-directive" => "script-src-elem",
            "document-uri" => "https://sway.vote/bills",
            "source-file" => ext_uri
          }
        }.to_json
        expect(SwayLogging).not_to receive(:warn)
        post "/csp-report", params: body, headers: {"CONTENT_TYPE" => "application/csp-report"}
        expect(response).to have_http_status(:no_content)
      end
    end

    it "drops extension violation when blocked-uri is an extension scheme" do
      body = {
        "csp-report" => {
          "blocked-uri" => "chrome-extension://abcd/eval.js",
          "violated-directive" => "script-src",
          "document-uri" => "https://sway.vote/bills",
          "source-file" => "https://sway.vote/app.js"
        }
      }.to_json
      expect(SwayLogging).not_to receive(:warn)
      post "/csp-report", params: body, headers: {"CONTENT_TYPE" => "application/csp-report"}
      expect(response).to have_http_status(:no_content)
    end

    it "does not rate-limit in test env — 200 requests all 204" do
      200.times do
        post "/csp-report", params: valid_body, headers: {"CONTENT_TYPE" => "application/csp-report"}
      end
      expect(response).to have_http_status(:no_content)
    end

    it "rate-limits in production after 100/min per IP" do
      allow(Sentry).to receive(:capture_message)
      with_rate_limit_enabled(:csp_report) do
        101.times do
          post "/csp-report", params: valid_body, headers: {"CONTENT_TYPE" => "application/csp-report"}
        end
        expect(response).to have_http_status(:too_many_requests)
      end
    end

    it "emits both CSP report-to and Reporting-Endpoints headers on non-/csp-report responses" do
      # Confirm the middleware and initializer send both the CSP directive and the Reporting-Endpoints header.
      get "/"  # any non-/csp-report route; root is safe
      csp_header = response.headers["Content-Security-Policy"].to_s.presence ||
        response.headers["Content-Security-Policy-Report-Only"].to_s
      expect(csp_header).to include("report-to csp-endpoint")
      expect(response.headers["Reporting-Endpoints"].to_s).to include('csp-endpoint="/csp-report"')
    end

    context "Sentry forwarding (production-gated)" do
      # @lat: [[error-reporting-in-tests#Why Sentry's methods are watched rather than the constant replaced]]
      before do
        allow(Sentry).to receive(:capture_message)
        allow(Rails.env).to receive(:production?).and_return(true)
      end

      it "forwards first occurrence of a unique violation to Sentry in production" do
        expect(Sentry).to receive(:capture_message).with(a_string_including("script-src"), hash_including(:level, :extra))
        post "/csp-report", params: valid_body, headers: {"CONTENT_TYPE" => "application/csp-report"}
      end

      # Sentry::Scope#set_extras runs `@extras.merge!(extras)`, so handing it
      # the raw Firefox reports+json Array raised "no implicit conversion of
      # Array into Hash" in production. The controller must always give Sentry
      # a Hash.
      it "wraps Firefox reports+json Array body in a Hash before passing to Sentry" do
        firefox_body = [
          {
            "age" => 1000,
            "type" => "csp-violation",
            "body" => {
              "blockedURL" => "https://evil.example.com/x.js",
              "effectiveDirective" => "script-src-elem",
              "documentURL" => "https://sway.vote/bills",
              "sourceFile" => "https://sway.vote/app.js"
            }
          }
        ].to_json

        expect(Sentry).to receive(:capture_message) do |_msg, opts|
          expect(opts[:extra]).to be_a(Hash)
        end
        post "/csp-report", params: firefox_body, headers: {"CONTENT_TYPE" => "application/reports+json"}
        expect(response).to have_http_status(:no_content)
      end

      it "deduplicates repeated identical violations within the hour (only every 10th is forwarded)" do
        # The test cache always returns nil, so fake a counter that really counts up per key
        count_box = [0]
        allow(Rails.cache).to receive(:increment).with(anything, anything, anything) do
          count_box[0] += 1
          count_box[0]
        end
        # The 1st is forwarded, the 2nd through 9th are dropped, the 10th is forwarded — 2 in all
        expect(Sentry).to receive(:capture_message).twice
        10.times do
          post "/csp-report", params: valid_body, headers: {"CONTENT_TYPE" => "application/csp-report"}
        end
      end
    end
  end
end
