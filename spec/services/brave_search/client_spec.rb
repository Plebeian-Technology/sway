# frozen_string_literal: true

require "rails_helper"

# @lat: [[llm-summaries#LLM bill summaries#Output is validated, not trusted#Cited local news reporting and domain-restricted web search#Pre-summarization search and article persistence]]
RSpec.describe BraveSearch::Client do
  let(:endpoint) { "https://api.search.brave.com/res/v1/web/search" }
  let(:api_key) { "test-brave-search-key-12345" }

  describe ".configured?" do
    it "returns true when BRAVE_SEARCH_API_KEY is present" do
      with_env("BRAVE_SEARCH_API_KEY" => "valid-key") do
        expect(described_class.configured?).to be(true)
      end
    end

    it "returns false when BRAVE_SEARCH_API_KEY is nil" do
      with_env("BRAVE_SEARCH_API_KEY" => nil) do
        expect(described_class.configured?).to be(false)
      end
    end

    it "returns false when BRAVE_SEARCH_API_KEY is empty" do
      with_env("BRAVE_SEARCH_API_KEY" => "") do
        expect(described_class.configured?).to be(false)
      end
    end

    it "returns false when BRAVE_SEARCH_API_KEY is whitespace-only" do
      with_env("BRAVE_SEARCH_API_KEY" => "   \t\n") do
        expect(described_class.configured?).to be(false)
      end
    end
  end

  describe ".redact_api_key" do
    it "redacts BRAVE_SEARCH_API_KEY when present in text" do
      with_env("BRAVE_SEARCH_API_KEY" => "brave-secret-token") do
        raw_text = "Error calling API with key brave-secret-token in query"
        redacted = described_class.redact_api_key(raw_text)

        expect(redacted).to eq("Error calling API with key [FILTERED] in query")
      end
    end

    it "redacts Anthropic sk-ant-* keys when present in text" do
      with_env("BRAVE_SEARCH_API_KEY" => nil) do
        raw_text = "Failed with sk-ant-api03-abcdef1234567890 key"
        redacted = described_class.redact_api_key(raw_text)

        expect(redacted).to eq("Failed with [FILTERED] key")
      end
    end

    it "redacts both Anthropic and Brave keys simultaneously" do
      with_env("BRAVE_SEARCH_API_KEY" => "brave-secret-token") do
        raw_text = "Brave key brave-secret-token and Claude key sk-ant-api03-abcdef12345"
        redacted = described_class.redact_api_key(raw_text)

        expect(redacted).to eq("Brave key [FILTERED] and Claude key [FILTERED]")
      end
    end

    it "leaves text unchanged when BRAVE_SEARCH_API_KEY is unset and no sensitive tokens exist" do
      with_env("BRAVE_SEARCH_API_KEY" => nil) do
        raw_text = "Standard error message without credentials"
        redacted = described_class.redact_api_key(raw_text)

        expect(redacted).to eq("Standard error message without credentials")
      end
    end

    it "handles nil input safely" do
      expect(described_class.redact_api_key(nil)).to eq("")
    end
  end

  describe "#initialize" do
    it "defaults connection to Sway::FaradayStack.brave_search" do
      client = described_class.new
      expect(client.instance_variable_get(:@connection)).to be_a(Faraday::Connection)
    end

    it "accepts an injected custom connection" do
      custom_conn = instance_double(Faraday::Connection)
      client = described_class.new(connection: custom_conn)
      expect(client.instance_variable_get(:@connection)).to be(custom_conn)
    end

    it "does not raise KeyError on initialize when BRAVE_SEARCH_API_KEY is unset" do
      with_env("BRAVE_SEARCH_API_KEY" => nil) do
        expect { described_class.new }.not_to raise_error
      end
    end
  end

  describe "#search" do
    subject(:client) { described_class.new }

    context "with empty or invalid inputs" do
      it "returns [] and makes no HTTP requests when query is nil" do
        conn = instance_double(Faraday::Connection)
        client = described_class.new(connection: conn)
        expect(conn).not_to receive(:get)

        with_env("BRAVE_SEARCH_API_KEY" => api_key) do
          result = client.search(query: nil, allowed_domains: ["thebanner.com"])
          expect(result).to eq([])
        end
      end

      it "returns [] and makes no HTTP requests when query is blank" do
        conn = instance_double(Faraday::Connection)
        client = described_class.new(connection: conn)
        expect(conn).not_to receive(:get)

        with_env("BRAVE_SEARCH_API_KEY" => api_key) do
          result = client.search(query: "   \t\n", allowed_domains: ["thebanner.com"])
          expect(result).to eq([])
        end
      end

      it "returns [] and makes no HTTP requests when allowed_domains is empty" do
        conn = instance_double(Faraday::Connection)
        client = described_class.new(connection: conn)
        expect(conn).not_to receive(:get)

        with_env("BRAVE_SEARCH_API_KEY" => api_key) do
          result = client.search(query: "24-0012 Housing", allowed_domains: [])
          expect(result).to eq([])
        end
      end

      it "returns [] and makes no HTTP requests when allowed_domains is nil" do
        conn = instance_double(Faraday::Connection)
        client = described_class.new(connection: conn)
        expect(conn).not_to receive(:get)

        with_env("BRAVE_SEARCH_API_KEY" => api_key) do
          result = client.search(query: "24-0012 Housing", allowed_domains: nil)
          expect(result).to eq([])
        end
      end

      it "returns [] and makes no HTTP requests when all allowed_domains are invalid" do
        conn = instance_double(Faraday::Connection)
        client = described_class.new(connection: conn)
        expect(conn).not_to receive(:get)

        with_env("BRAVE_SEARCH_API_KEY" => api_key) do
          result = client.search(
            query: "24-0012 Housing",
            allowed_domains: ["invalid-domain", "http://127.0.0.1", "localhost"]
          )
          expect(result).to eq([])
        end
      end

      it "does not raise KeyError when inputs are invalid and BRAVE_SEARCH_API_KEY is unset" do
        with_env("BRAVE_SEARCH_API_KEY" => nil) do
          expect {
            client.search(query: "", allowed_domains: ["thebanner.com"])
          }.not_to raise_error
        end
      end
    end

    context "with query truncation and sanitization" do
      it "truncates base query words to at most 20 words" do
        long_query = "word " * 30
        expected_query = ("word " * 20).strip

        with_env("BRAVE_SEARCH_API_KEY" => api_key) do
          stub = stub_request(:get, %r{\Ahttps://api\.search\.brave\.com/res/v1/web/search})
            .with(
              query: hash_including("q" => "#{expected_query} site:thebanner.com"),
              headers: {"X-Subscription-Token" => api_key}
            )
            .to_return(status: 200, body: '{"web": {"results": []}}', headers: {"Content-Type" => "application/json"})

          client.search(query: long_query, allowed_domains: ["thebanner.com"])
          expect(stub).to have_been_requested
        end
      end

      it "truncates base query characters to at most 160 characters" do
        long_word = "a" * 200

        with_env("BRAVE_SEARCH_API_KEY" => api_key) do
          stub = stub_request(:get, %r{\Ahttps://api\.search\.brave\.com/res/v1/web/search})
            .with(
              query: hash_including("q" => "#{"a" * 160} site:thebanner.com"),
              headers: {"X-Subscription-Token" => api_key}
            )
            .to_return(status: 200, body: '{"web": {"results": []}}', headers: {"Content-Type" => "application/json"})

          client.search(query: long_word, allowed_domains: ["thebanner.com"])
          expect(stub).to have_been_requested
        end
      end

      it "collapses whitespace and strips null bytes from query" do
        query_with_null = "24-0012 \u0000 Housing  \n\t Bill"

        with_env("BRAVE_SEARCH_API_KEY" => api_key) do
          stub = stub_request(:get, %r{\Ahttps://api\.search\.brave\.com/res/v1/web/search})
            .with(
              query: hash_including("q" => "24-0012 Housing Bill site:thebanner.com"),
              headers: {"X-Subscription-Token" => api_key}
            )
            .to_return(status: 200, body: '{"web": {"results": []}}', headers: {"Content-Type" => "application/json"})

          client.search(query: query_with_null, allowed_domains: ["thebanner.com"])
          expect(stub).to have_been_requested
        end
      end
    end

    context "with domain query formatting and batching" do
      it "formats a single domain query without parentheses" do
        with_env("BRAVE_SEARCH_API_KEY" => api_key) do
          stub = stub_request(:get, %r{\Ahttps://api\.search\.brave\.com/res/v1/web/search})
            .with(
              query: {"q" => "24-0012 Housing site:thebanner.com", "count" => "20"},
              headers: {"X-Subscription-Token" => api_key}
            )
            .to_return(status: 200, body: '{"web": {"results": []}}', headers: {"Content-Type" => "application/json"})

          client.search(query: "24-0012 Housing", allowed_domains: ["thebanner.com"])
          expect(stub).to have_been_requested
        end
      end

      it "formats multiple domains with parenthesized OR clauses" do
        with_env("BRAVE_SEARCH_API_KEY" => api_key) do
          stub = stub_request(:get, %r{\Ahttps://api\.search\.brave\.com/res/v1/web/search})
            .with(
              query: {
                "q" => "24-0012 Housing (site:thebanner.com OR site:baltimoresun.com)",
                "count" => "20"
              },
              headers: {"X-Subscription-Token" => api_key}
            )
            .to_return(status: 200, body: '{"web": {"results": []}}', headers: {"Content-Type" => "application/json"})

          client.search(query: "24-0012 Housing", allowed_domains: ["thebanner.com", "baltimoresun.com"])
          expect(stub).to have_been_requested
        end
      end

      it "batches a large domain list so that every request satisfies q.length <= 400 and words <= 50" do
        long_base_query = "A" * 150
        domains = (1..12).map { |i| "longdomain#{i}-baltimore-community-news-outlet.org" }

        with_env("BRAVE_SEARCH_API_KEY" => api_key) do
          recorded_queries = []
          stub = stub_request(:get, %r{\Ahttps://api\.search\.brave\.com/res/v1/web/search})
            .with { |req|
              q = req.uri.query_values["q"]
              recorded_queries << q
              true
            }
            .to_return(status: 200, body: '{"web": {"results": []}}', headers: {"Content-Type" => "application/json"})

          client.search(query: long_base_query, allowed_domains: domains)

          expect(stub).to have_been_requested.at_least_twice
          expect(recorded_queries.size).to be >= 2
          recorded_queries.each do |q|
            expect(q.length).to be <= 400
            expect(q.split(/\s+/).size).to be <= 50
          end
        end
      end

      it "clamps count parameter to 1..20" do
        with_env("BRAVE_SEARCH_API_KEY" => api_key) do
          stub_max = stub_request(:get, %r{\Ahttps://api\.search\.brave\.com/res/v1/web/search})
            .with(query: hash_including("count" => "20"))
            .to_return(status: 200, body: '{"web": {"results": []}}', headers: {"Content-Type" => "application/json"})

          client.search(query: "Housing", allowed_domains: ["thebanner.com"], count: 50)
          expect(stub_max).to have_been_requested

          stub_min = stub_request(:get, %r{\Ahttps://api\.search\.brave\.com/res/v1/web/search})
            .with(query: hash_including("count" => "1"))
            .to_return(status: 200, body: '{"web": {"results": []}}', headers: {"Content-Type" => "application/json"})

          client.search(query: "Housing", allowed_domains: ["thebanner.com"], count: 0)
          expect(stub_min).to have_been_requested
        end
      end
    end

    context "with candidate hash mapping and deduplication" do
      it "maps web.results items into candidate hashes" do
        body_json = {
          "web" => {
            "results" => [
              {
                "url" => "https://thebanner.com/community/housing-bill-24-0012",
                "title" => "Baltimore Council passes housing measure",
                "description" => "A deep dive into 24-0012 passed by city council.",
                "extra_snippets" => ["Council voted 14-1 in favor."],
                "page_age" => "2024-10-15T12:00:00Z",
                "profile" => {"name" => "The Baltimore Banner"}
              },
              {
                "url" => "https://baltimoresun.com/news/council-24-0012",
                "title" => "Sun coverage of housing bill",
                "description" => "Sun report on Baltimore housing legislation.",
                "age" => "3 days ago"
              },
              {
                "url" => "",
                "title" => "Empty url result"
              }
            ]
          }
        }.to_json

        with_env("BRAVE_SEARCH_API_KEY" => api_key) do
          stub_request(:get, %r{\Ahttps://api\.search\.brave\.com/res/v1/web/search})
            .to_return(status: 200, body: body_json, headers: {"Content-Type" => "application/json"})

          results = client.search(query: "24-0012 Housing", allowed_domains: ["thebanner.com", "baltimoresun.com"])

          expect(results.size).to eq(2)
          expect(results[0]).to eq(
            "url" => "https://thebanner.com/community/housing-bill-24-0012",
            "title" => "Baltimore Council passes housing measure",
            "cited_text" => "A deep dive into 24-0012 passed by city council. Council voted 14-1 in favor.",
            "published_at" => "2024-10-15T12:00:00Z",
            "outlet_name" => "The Baltimore Banner"
          )
          expect(results[1]).to eq(
            "url" => "https://baltimoresun.com/news/council-24-0012",
            "title" => "Sun coverage of housing bill",
            "cited_text" => "Sun report on Baltimore housing legislation.",
            "published_at" => "3 days ago"
          )
        end
      end

      it "truncates cited_text to 150 characters" do
        long_description = "B" * 200
        body_json = {
          "web" => {
            "results" => [
              {
                "url" => "https://thebanner.com/article",
                "title" => "Title",
                "description" => long_description
              }
            ]
          }
        }.to_json

        with_env("BRAVE_SEARCH_API_KEY" => api_key) do
          stub_request(:get, %r{\Ahttps://api\.search\.brave\.com/res/v1/web/search})
            .to_return(status: 200, body: body_json, headers: {"Content-Type" => "application/json"})

          results = client.search(query: "Housing", allowed_domains: ["thebanner.com"])
          expect(results.first["cited_text"]).to eq("B" * 150)
        end
      end

      it "deduplicates results across batches by canonical URL" do
        batch1_body = {
          "web" => {
            "results" => [
              {
                "url" => "https://thebanner.com/housing?utm_source=twitter",
                "title" => "Housing Story Version 1"
              }
            ]
          }
        }.to_json

        batch2_body = {
          "web" => {
            "results" => [
              {
                "url" => "https://thebanner.com/housing",
                "title" => "Housing Story Version 2"
              }
            ]
          }
        }.to_json

        allow(SwayLocale::DocumentReader).to receive(:normalize_news_source_url)
          .with("https://thebanner.com/housing?utm_source=twitter")
          .and_return("https://thebanner.com/housing")
        allow(SwayLocale::DocumentReader).to receive(:normalize_news_source_url)
          .with("https://thebanner.com/housing")
          .and_return("https://thebanner.com/housing")

        conn = instance_double(Faraday::Connection)
        client = described_class.new(connection: conn)

        resp1 = instance_double(Faraday::Response, status: 200, body: batch1_body)
        resp2 = instance_double(Faraday::Response, status: 200, body: batch2_body)

        with_env("BRAVE_SEARCH_API_KEY" => api_key) do
          expect(conn).to receive(:get).twice.and_return(resp1, resp2)
          allow(client).to receive(:partition_batches).and_return([["d1.com"], ["d2.com"]])

          results = client.search(query: "Housing", allowed_domains: ["d1.com", "d2.com"])
          expect(results.size).to eq(1)
          expect(results.first["title"]).to eq("Housing Story Version 1")
        end
      end
    end

    context "with error handling and credential redaction" do
      it "raises BraveSearch::Client::Error on HTTP 401 with redacted message" do
        error_body = "Unauthorized token: #{api_key}"

        with_env("BRAVE_SEARCH_API_KEY" => api_key) do
          stub_request(:get, %r{\Ahttps://api\.search\.brave\.com/res/v1/web/search})
            .to_return(status: 401, body: error_body, headers: {"Content-Type" => "text/plain"})

          expect {
            client.search(query: "Housing", allowed_domains: ["thebanner.com"])
          }.to raise_error(
            BraveSearch::Client::Error,
            "Brave Search API HTTP 401: Unauthorized token: [FILTERED]"
          )
        end
      end

      it "raises BraveSearch::Client::Error on HTTP 422" do
        with_env("BRAVE_SEARCH_API_KEY" => api_key) do
          stub_request(:get, %r{\Ahttps://api\.search\.brave\.com/res/v1/web/search})
            .to_return(status: 422, body: "Query too long", headers: {"Content-Type" => "text/plain"})

          expect {
            client.search(query: "Housing", allowed_domains: ["thebanner.com"])
          }.to raise_error(BraveSearch::Client::Error, /Brave Search API HTTP 422: Query too long/)
        end
      end

      it "raises BraveSearch::Client::Error on HTTP 429 rate limit" do
        with_env("BRAVE_SEARCH_API_KEY" => api_key) do
          stub_request(:get, %r{\Ahttps://api\.search\.brave\.com/res/v1/web/search})
            .to_return(status: 429, body: "Rate limit exceeded", headers: {"Content-Type" => "text/plain"})

          expect {
            client.search(query: "Housing", allowed_domains: ["thebanner.com"])
          }.to raise_error(BraveSearch::Client::Error, /Brave Search API HTTP 429: Rate limit exceeded/)
        end
      end

      it "raises BraveSearch::Client::Error on HTTP 500 server error" do
        with_env("BRAVE_SEARCH_API_KEY" => api_key) do
          stub_request(:get, %r{\Ahttps://api\.search\.brave\.com/res/v1/web/search})
            .to_return(status: 500, body: "Internal Server Error", headers: {"Content-Type" => "text/plain"})

          expect {
            client.search(query: "Housing", allowed_domains: ["thebanner.com"])
          }.to raise_error(BraveSearch::Client::Error, /Brave Search API HTTP 500: Internal Server Error/)
        end
      end

      it "raises BraveSearch::Client::Error on Faraday connection error" do
        with_env("BRAVE_SEARCH_API_KEY" => api_key) do
          stub_request(:get, %r{\Ahttps://api\.search\.brave\.com/res/v1/web/search})
            .to_raise(Faraday::ConnectionFailed.new("Connection reset by peer"))

          expect {
            client.search(query: "Housing", allowed_domains: ["thebanner.com"])
          }.to raise_error(BraveSearch::Client::Error, /Faraday::ConnectionFailed: Connection reset by peer/)
        end
      end

      it "raises BraveSearch::Client::Error on Faraday timeout error" do
        with_env("BRAVE_SEARCH_API_KEY" => api_key) do
          stub_request(:get, %r{\Ahttps://api\.search\.brave\.com/res/v1/web/search})
            .to_raise(Faraday::TimeoutError.new("Execution expired"))

          expect {
            client.search(query: "Housing", allowed_domains: ["thebanner.com"])
          }.to raise_error(BraveSearch::Client::Error, /Faraday::TimeoutError: Execution expired/)
        end
      end

      it "raises BraveSearch::Client::Error on malformed JSON response" do
        with_env("BRAVE_SEARCH_API_KEY" => api_key) do
          stub_request(:get, %r{\Ahttps://api\.search\.brave\.com/res/v1/web/search})
            .to_return(status: 200, body: "not valid json {", headers: {"Content-Type" => "application/json"})

          expect {
            client.search(query: "Housing", allowed_domains: ["thebanner.com"])
          }.to raise_error(BraveSearch::Client::Error, /JSON::ParserError/)
        end
      end

      it "redacts sk-ant-* keys from error messages" do
        with_env("BRAVE_SEARCH_API_KEY" => api_key) do
          stub_request(:get, %r{\Ahttps://api\.search\.brave\.com/res/v1/web/search})
            .to_raise(Faraday::ClientError.new("Error with sk-ant-api03-abcdef1234567890"))

          expect {
            client.search(query: "Housing", allowed_domains: ["thebanner.com"])
          }.to raise_error(BraveSearch::Client::Error, /\[FILTERED\]/)
        end
      end
    end
  end
end
