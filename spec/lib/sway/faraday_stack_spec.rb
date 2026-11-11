# frozen_string_literal: true

require "rails_helper"

RSpec.describe Sway::FaradayStack do
  describe "LEGISTAR_DEFAULTS" do
    it "is frozen and matches the retry contract" do
      expect(described_class::LEGISTAR_DEFAULTS).to be_frozen
      expect(described_class::LEGISTAR_DEFAULTS).to include(
        max: 3,
        interval: 0.5,
        backoff_factor: 2,
        retry_statuses: [429, 500, 502, 503, 504],
        methods: %i[get post]
      )
    end
  end

  describe "LEGISTAR_ATTACHMENT_DEFAULTS" do
    it "is frozen and sets retry count to max 1 (two attempts total)" do
      expect(described_class::LEGISTAR_ATTACHMENT_DEFAULTS).to be_frozen
      expect(described_class::LEGISTAR_ATTACHMENT_DEFAULTS).to include(
        max: 1,
        interval: 0.5,
        backoff_factor: 2,
        retry_statuses: [429, 500, 502, 503, 504],
        methods: %i[get post],
        exceptions: described_class::TRANSPORT_RETRY_EXCEPTIONS
      )
    end
  end

  describe "LLAMACPP_DEFAULTS" do
    it "is frozen and matches the retry contract for llama.cpp" do
      expect(described_class::LLAMACPP_DEFAULTS).to be_frozen
      expect(described_class::LLAMACPP_DEFAULTS).to include(
        max: 2,
        interval: 1.0,
        backoff_factor: 2,
        retry_statuses: [500, 502, 503, 504],
        methods: %i[post]
      )
    end
  end

  # @lat: [[outbound-fetch-safety#A dropped connection is retried where repeating is safe]]
  describe "TRANSPORT_RETRY_EXCEPTIONS" do
    it "extends faraday-retry's defaults with connection-reset classes and is frozen" do
      expect(described_class::TRANSPORT_RETRY_EXCEPTIONS).to be_frozen
      expect(described_class::TRANSPORT_RETRY_EXCEPTIONS)
        .to include(*Faraday::Retry::Middleware::DEFAULT_EXCEPTIONS)
      expect(described_class::TRANSPORT_RETRY_EXCEPTIONS)
        .to include(Faraday::ConnectionFailed, Faraday::SSLError)
    end

    it "wires the transport exceptions into every idempotent GET profile" do
      [described_class::LEGISTAR_DEFAULTS, described_class::OPEN_DATA_DEFAULTS,
        described_class::GITHUB_DEFAULTS].each do |profile|
        expect(profile[:exceptions]).to include(Faraday::ConnectionFailed, Faraday::SSLError)
      end
    end

    it "does NOT add connection-reset retries to the POST-only llama.cpp profile" do
      # Re-sending a POST that may already have been half delivered could do the
      # work twice, so the llama profile keeps faraday-retry's timeout-only list.
      expect(described_class::LLAMACPP_DEFAULTS).not_to have_key(:exceptions)
    end
  end

  describe "transport-level retry behavior" do
    it "retries Faraday::SSLError (mid-read TLS EOF) on the Legistar profile and succeeds next attempt" do
      attempts = 0
      conn = Faraday.new do |c|
        c.request(:retry, described_class::LEGISTAR_DEFAULTS)
        c.adapter(:test) do |stub|
          stub.get("/ping") do
            attempts += 1
            raise Faraday::SSLError, "SSL_read: unexpected eof while reading" if attempts == 1

            [200, {}, "ok"]
          end
        end
      end

      response = conn.get("/ping")

      expect(response.status).to eq(200)
      expect(attempts).to eq(2)
    end

    it "does NOT retry Faraday::SSLError on the llama.cpp profile (raises on first attempt)" do
      attempts = 0
      conn = Faraday.new do |c|
        c.request(:retry, described_class::LLAMACPP_DEFAULTS)
        c.adapter(:test) do |stub|
          stub.post("/v1/chat/completions") do
            attempts += 1
            raise Faraday::SSLError, "SSL_read: unexpected eof while reading"
          end
        end
      end

      expect { conn.post("/v1/chat/completions") }.to raise_error(Faraday::SSLError)
      expect(attempts).to eq(1)
    end
  end

  describe "retry attempt counts on Legistar profiles" do
    it "proves legistar_attachment connection makes exactly 2 attempts against a repeatedly failing stub" do
      req_stub = stub_request(:get, "https://webapi.legistar.com/test-attachment-failure")
        .to_raise(Faraday::ConnectionFailed.new("connection reset"))

      conn = described_class.legistar_attachment
      expect { conn.get("/test-attachment-failure") }.to raise_error(Faraday::ConnectionFailed)
      expect(req_stub).to have_been_made.times(2)
    end

    it "proves non-attachment legistar connection still makes exactly 4 attempts against a repeatedly failing stub" do
      req_stub = stub_request(:get, "https://webapi.legistar.com/test-non-attachment-failure")
        .to_raise(Faraday::ConnectionFailed.new("connection reset"))

      conn = described_class.legistar
      expect { conn.get("/test-non-attachment-failure") }.to raise_error(Faraday::ConnectionFailed)
      expect(req_stub).to have_been_made.times(4)
    end
  end

  describe ".build" do
    it "returns a Faraday::Connection with retry middleware mounted" do
      conn = described_class.build(base_url: "https://example.test")

      expect(conn).to be_a(Faraday::Connection)
      expect(conn.url_prefix.to_s.start_with?("https://example.test")).to be(true)
      expect(conn.builder.handlers).to include(Faraday::Retry::Middleware)
    end

    it "applies the requested timeout" do
      conn = described_class.build(base_url: "https://example.test", timeout_seconds: 17)

      expect(conn.options.timeout).to eq(17)
    end

    it "yields the builder so callers can mount additional middleware" do
      yielded = nil
      described_class.build(base_url: "https://example.test") do |builder|
        yielded = builder
      end

      expect(yielded).to be_a(Faraday::Connection)
    end
  end

  # @lat: [[faraday-stack-retry-and-connection-design#Why the .legistar env-override specs use with_app_config, not with_env]]
  describe ".legistar" do
    it "honors LEGISTAR_API_BASE_URL when set" do
      with_app_config(:upstream, legistar_api_base_url: "https://legistar.example/v1") do
        conn = described_class.legistar

        expect(conn).to be_a(Faraday::Connection)
        expect(conn.url_prefix.to_s.start_with?("https://legistar.example/v1")).to be(true)
        expect(conn.builder.handlers).to include(Faraday::Retry::Middleware)
      end
    end

    it "defaults to the public Legistar base URL when unset" do
      with_app_config(:upstream, legistar_api_base_url: nil) do
        conn = described_class.legistar

        expect(conn.url_prefix.to_s.start_with?("https://webapi.legistar.com")).to be(true)
      end
    end

    # Blank counts as absent. ENV.fetch("X", default) hands back "" for
    # a set-but-empty variable, not the default -- Sway::Settings::Base's
    # blank repair is what closes that trap here.
    it "falls back to the default when set to an empty string" do
      with_app_config(:upstream, legistar_api_base_url: "") do
        conn = described_class.legistar

        expect(conn.url_prefix.to_s.start_with?("https://webapi.legistar.com")).to be(true)
      end
    end

    it "falls back to the default when set to only whitespace" do
      with_app_config(:upstream, legistar_api_base_url: "   ") do
        conn = described_class.legistar

        expect(conn.url_prefix.to_s.start_with?("https://webapi.legistar.com")).to be(true)
      end
    end

    it "strips surrounding whitespace from a non-blank value" do
      with_app_config(:upstream, legistar_api_base_url: "https://legistar.example/v1\n") do
        conn = described_class.legistar

        expect(conn.url_prefix.to_s.start_with?("https://legistar.example/v1")).to be(true)
      end
    end

    it "reads a real LEGISTAR_API_BASE_URL environment variable, source-traced to it by name" do
      with_env("LEGISTAR_API_BASE_URL" => "https://legistar.example/v1") do
        instance = Sway::Settings::Upstream.new

        expect(instance.legistar_api_base_url).to eq("https://legistar.example/v1")
        expect(instance.to_source_trace["legistar_api_base_url"][:source])
          .to eq(type: :env, key: "LEGISTAR_API_BASE_URL")
      end
    end
  end

  describe ".github" do
    it "defaults to the public GitHub base URL" do
      with_app_config(:upstream, law_xml_github_base_url: nil) do
        expect(described_class.github.url_prefix.to_s.start_with?("https://github.com")).to be(true)
      end
    end
  end

  describe ".open_states" do
    it "defaults to the public OpenStates v3 base URL" do
      with_app_config(:upstream, openstates_api_base_url: nil) do
        expect(described_class.open_states.url_prefix.to_s.start_with?("https://v3.openstates.org")).to be(true)
      end
    end
  end

  # The congress.gov v3 profile, used by the weekly CongressRefresh roster fetch.
  describe ".congress_gov" do
    it "honors CONGRESS_GOV_API_BASE_URL when set and mounts the bounded-retry stack" do
      with_app_config(:upstream, congress_gov_api_base_url: "https://congress.example/v3") do
        conn = described_class.congress_gov

        expect(conn).to be_a(Faraday::Connection)
        expect(conn.url_prefix.to_s.start_with?("https://congress.example/v3")).to be(true)
        expect(conn.builder.handlers).to include(Faraday::Retry::Middleware)
        expect(conn.options.timeout).to eq(30)
      end
    end

    it "defaults to the public congress.gov base URL when unset" do
      with_app_config(:upstream, congress_gov_api_base_url: nil) do
        expect(described_class.congress_gov.url_prefix.to_s.start_with?("https://api.congress.gov/v3")).to be(true)
      end
    end

    it "mounts CongressGovErrorReporter outer to Faraday::Retry::Middleware" do
      conn = described_class.congress_gov
      handlers = conn.builder.handlers

      expect(handlers.first).to eq(described_class::CongressGovErrorReporter)
      expect(handlers).to include(Faraday::Retry::Middleware)
      reporter_idx = handlers.index { |h| h == described_class::CongressGovErrorReporter }
      retry_idx = handlers.index { |h| h == Faraday::Retry::Middleware }
      expect(reporter_idx).to be < retry_idx
    end

    it "reports client errors (401, 403, 404) to Sentry once with level: :error, constant message, and fingerprint" do
      allow(Sentry).to receive(:capture_message)
      conn = described_class.congress_gov

      [401, 403, 404].each do |status_code|
        stub_request(:get, "https://api.congress.gov/v3/test-#{status_code}?api_key=secret_token&format=json")
          .to_return(status: status_code, body: "Error #{status_code}")

        response = conn.get("/v3/test-#{status_code}", {api_key: "secret_token", format: "json"})

        expect(response.status).to eq(status_code)
        expect(Sentry).to have_received(:capture_message).with(
          "Congress.gov API HTTP error",
          level: :error,
          fingerprint: ["congress_gov_http", status_code.to_s, "/v3/test-#{status_code}"],
          extra: {
            status: status_code,
            method: :get,
            path: "/v3/test-#{status_code}",
            url: "https://api.congress.gov/v3/test-#{status_code}?api_key=[FILTERED]&format=json"
          }
        ).once
      end
    end

    it "reports persistent 500 error to Sentry exactly once after retry exhaustion" do
      allow(Sentry).to receive(:capture_message)
      req_stub = stub_request(:get, "https://api.congress.gov/v3/test-500?api_key=secret_token")
        .to_return(status: 500, body: "Internal Server Error")

      conn = described_class.congress_gov
      response = conn.get("/v3/test-500", {api_key: "secret_token"})

      expect(response.status).to eq(500)
      expect(req_stub).to have_been_made.times(4)
      expect(Sentry).to have_received(:capture_message).with(
        "Congress.gov API HTTP error",
        level: :error,
        fingerprint: ["congress_gov_http", "500", "/v3/test-500"],
        extra: {
          status: 500,
          method: :get,
          path: "/v3/test-500",
          url: "https://api.congress.gov/v3/test-500?api_key=[FILTERED]"
        }
      ).once
    end

    it "groups errors across resource instances by parameterizing numeric path segments in the fingerprint" do
      allow(Sentry).to receive(:capture_message)
      stub_request(:get, "https://api.congress.gov/v3/bill/119/hr/1?api_key=secret_token")
        .to_return(status: 404, body: "Not Found")
      stub_request(:get, "https://api.congress.gov/v3/bill/119/hr/2?api_key=secret_token")
        .to_return(status: 404, body: "Not Found")

      conn = described_class.congress_gov
      conn.get("/v3/bill/119/hr/1", {api_key: "secret_token"})
      conn.get("/v3/bill/119/hr/2", {api_key: "secret_token"})

      expect(Sentry).to have_received(:capture_message).with(
        "Congress.gov API HTTP error",
        level: :error,
        fingerprint: ["congress_gov_http", "404", "/v3/bill/:n/hr/:n"],
        extra: {
          status: 404,
          method: :get,
          path: "/v3/bill/119/hr/1",
          url: "https://api.congress.gov/v3/bill/119/hr/1?api_key=[FILTERED]"
        }
      ).once

      expect(Sentry).to have_received(:capture_message).with(
        "Congress.gov API HTTP error",
        level: :error,
        fingerprint: ["congress_gov_http", "404", "/v3/bill/:n/hr/:n"],
        extra: {
          status: 404,
          method: :get,
          path: "/v3/bill/119/hr/2",
          url: "https://api.congress.gov/v3/bill/119/hr/2?api_key=[FILTERED]"
        }
      ).once
    end

    it "suppresses Sentry reporting on 404 for unpublished house-vote endpoints" do
      allow(Sentry).to receive(:capture_message)
      stub_request(:get, "https://api.congress.gov/v3/house-vote/119/2/74/members?api_key=secret_token")
        .to_return(status: 404, body: "Not Found")

      conn = described_class.congress_gov
      response = conn.get("/v3/house-vote/119/2/74/members", {api_key: "secret_token"})

      expect(response.status).to eq(404)
      expect(Sentry).not_to have_received(:capture_message)
    end

    it "reports non-404 errors on house-vote endpoints to Sentry once after retries" do
      allow(Sentry).to receive(:capture_message)
      stub_request(:get, "https://api.congress.gov/v3/house-vote/119/2/74/members?api_key=secret_token")
        .to_return(status: 403, body: "Forbidden")

      conn = described_class.congress_gov
      response = conn.get("/v3/house-vote/119/2/74/members", {api_key: "secret_token"})

      expect(response.status).to eq(403)
      expect(Sentry).to have_received(:capture_message).with(
        "Congress.gov API HTTP error",
        level: :error,
        fingerprint: ["congress_gov_http", "403", "/v3/house-vote/:n/:n/:n/members"],
        extra: {
          status: 403,
          method: :get,
          path: "/v3/house-vote/119/2/74/members",
          url: "https://api.congress.gov/v3/house-vote/119/2/74/members?api_key=[FILTERED]"
        }
      ).once
    end

    it "does not report to Sentry when a transient 503 succeeds on retry" do
      allow(Sentry).to receive(:capture_message)
      req_stub = stub_request(:get, "https://api.congress.gov/v3/test-transient?api_key=secret_token")
        .to_return(
          {status: 503, body: "Service Unavailable"},
          {status: 200, body: '{"ok":true}'}
        )

      conn = described_class.congress_gov
      response = conn.get("/v3/test-transient", {api_key: "secret_token"})

      expect(response.status).to eq(200)
      expect(req_stub).to have_been_made.times(2)
      expect(Sentry).not_to have_received(:capture_message)
    end

    it "does not report 200 OK or 301 Redirect to Sentry" do
      allow(Sentry).to receive(:capture_message)
      stub_request(:get, "https://api.congress.gov/v3/test-200?api_key=secret_token")
        .to_return(status: 200, body: '{"ok":true}')
      stub_request(:get, "https://api.congress.gov/v3/test-301?api_key=secret_token")
        .to_return(status: 301, headers: {"Location" => "https://api.congress.gov/v3/other"})

      conn = described_class.congress_gov
      resp_200 = conn.get("/v3/test-200", {api_key: "secret_token"})
      resp_301 = conn.get("/v3/test-301", {api_key: "secret_token"})

      expect(resp_200.status).to eq(200)
      expect(resp_301.status).to eq(301)
      expect(Sentry).not_to have_received(:capture_message)
    end
  end

  describe ".congress_legislators" do
    it "defaults to the unitedstates/congress-legislators base URL, keeping its trailing slash" do
      with_app_config(:upstream, congress_legislators_base_url: nil) do
        expect(described_class.congress_legislators.url_prefix.to_s).to end_with("/")
        expect(described_class.congress_legislators.url_prefix.to_s.start_with?(
          "https://unitedstates.github.io/congress-legislators/"
        )).to be(true)
      end
    end
  end

  describe ".brave_search" do
    it "honors BRAVE_SEARCH_API_BASE_URL when set, mounts retry middleware, sets timeout to 15, and sets Accept header" do
      with_app_config(:upstream, brave_search_api_base_url: "https://brave.example") do
        conn = described_class.brave_search

        expect(conn).to be_a(Faraday::Connection)
        expect(conn.url_prefix.to_s.start_with?("https://brave.example")).to be(true)
        expect(conn.builder.handlers).to include(Faraday::Retry::Middleware)
        expect(conn.options.timeout).to eq(15)
        expect(conn.headers["Accept"]).to eq("application/json")
      end
    end

    it "honors a custom timeout_seconds argument" do
      with_app_config(:upstream, brave_search_api_base_url: "https://brave.example") do
        conn = described_class.brave_search(timeout_seconds: 45)

        expect(conn.options.timeout).to eq(45)
      end
    end

    it "defaults to the public Brave Search API base URL when unset" do
      with_app_config(:upstream, brave_search_api_base_url: nil) do
        conn = described_class.brave_search

        expect(conn.url_prefix.to_s.start_with?("https://api.search.brave.com")).to be(true)
      end
    end

    it "falls back to the default when set to an empty string" do
      with_app_config(:upstream, brave_search_api_base_url: "") do
        conn = described_class.brave_search

        expect(conn.url_prefix.to_s.start_with?("https://api.search.brave.com")).to be(true)
      end
    end

    it "falls back to the default when set to only whitespace" do
      with_app_config(:upstream, brave_search_api_base_url: "   ") do
        conn = described_class.brave_search

        expect(conn.url_prefix.to_s.start_with?("https://api.search.brave.com")).to be(true)
      end
    end

    it "strips surrounding whitespace from a non-blank value" do
      with_app_config(:upstream, brave_search_api_base_url: "https://brave.example\n") do
        conn = described_class.brave_search

        expect(conn.url_prefix.to_s.start_with?("https://brave.example")).to be(true)
      end
    end

    it "reads a real BRAVE_SEARCH_API_BASE_URL environment variable, source-traced to it by name" do
      with_env("BRAVE_SEARCH_API_BASE_URL" => "https://brave.example") do
        instance = Sway::Settings::Upstream.new

        expect(instance.brave_search_api_base_url).to eq("https://brave.example")
        expect(instance.to_source_trace["brave_search_api_base_url"][:source])
          .to eq(type: :env, key: "BRAVE_SEARCH_API_BASE_URL")
      end
    end
  end

  # @lat: [[faraday-stack-retry-and-connection-design#Why there is no .llamacpp connection method]]
  # The deadline is covered in spec/services/llm/llamacpp_adapter_spec.rb.
  describe "llama.cpp" do
    it "supplies retry options but no connection" do
      expect(described_class).not_to respond_to(:llamacpp)
      expect(described_class::LLAMACPP_DEFAULTS).to be_frozen
    end
  end

  # Helper: set or unset environment variables just for the block, then restore
  # them (the same helper as in spec/lib/rate_limit_config_spec.rb).
end
