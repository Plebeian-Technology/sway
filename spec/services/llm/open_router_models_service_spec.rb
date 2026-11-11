# frozen_string_literal: true

require "rails_helper"

RSpec.describe Llm::OpenRouterModelsService do
  include_context "with in-memory Rails.cache"

  before do
    allow(EnvSecret).to receive(:read).and_call_original
    allow(EnvSecret).to receive(:read).with("OPENROUTER_API_KEY").and_return(nil)
    allow(EnvSecret).to receive(:read).with("OPEN_ROUTER_API_KEY").and_return(nil)

    @raw_models_data = [
      {
        "id" => "openai/gpt-4o-mini",
        "name" => "OpenAI: GPT-4o-mini",
        "supported_parameters" => ["structured_outputs", "tools"],
        "reasoning" => {"supported_efforts" => []}
      },
      {
        "id" => "deepseek/deepseek-r1",
        "name" => "DeepSeek: R1",
        "supported_parameters" => ["structured_outputs", "reasoning"],
        "reasoning" => {"supported_efforts" => ["low", "medium", "high"]}
      },
      {
        "id" => "anthropic/claude-3.7-sonnet",
        "name" => "Anthropic: Claude 3.7 Sonnet",
        "supported_parameters" => ["structured_outputs", "reasoning_effort"],
        "reasoning" => {"supported_efforts" => []}
      },
      {
        "id" => "meta-llama/llama-3.3-70b-instruct",
        "name" => "",
        "supported_parameters" => ["structured_outputs"]
      }
    ]

    @raw_response_body = {"data" => @raw_models_data}.to_json
    @cached_models = [
      {id: "cached/model-1", label: "Cached Model", supports_reasoning: false}.freeze
    ].freeze
    @raw_decision_models_data = [
      {
        "id" => "scaledown/classify-1",
        "name" => "ScaleDown: Classify",
        "architecture" => {"output_modalities" => ["decisions"], "modality" => "text->text"}
      },
      {
        "id" => "~typesafe/jev-latest",
        "name" => "Jev Latest",
        "architecture" => {"output_modalities" => ["decisions"]}
      },
      {
        "id" => "~perplexity/pplx-decider-latest",
        "name" => "Perplexity Decider Latest",
        "architecture" => {"output_modalities" => ["decisions"]}
      },
      {
        "id" => "~perplexity/pplx-decider-flash-latest",
        "name" => "",
        "architecture" => {"output_modalities" => ["decisions"]}
      }
    ]
    @raw_decision_response_body = {"data" => @raw_decision_models_data}.to_json
    @cached_decision_models = [
      {id: "cached/decision-model-1", label: "Cached Decision Model", supports_reasoning: false, mode: :decision}.freeze
    ].freeze
  end

  describe "constants" do
    it "defines MODELS_ENDPOINT as the OpenRouter structured-outputs URL" do
      expect(described_class::MODELS_ENDPOINT).to eq("https://openrouter.ai/api/v1/models?supported_parameters=structured_outputs")
    end

    it "defines DECISION_MODELS_ENDPOINT as the OpenRouter decision models URL" do
      expect(described_class::DECISION_MODELS_ENDPOINT).to eq("https://openrouter.ai/api/v1/models?output_modalities=decisions")
    end

    it "defines CACHE_KEY for solid cache storage" do
      expect(described_class::CACHE_KEY).to eq("llm/openrouter/structured_output_models/v1")
    end

    it "defines DECISION_CACHE_KEY for decision models storage" do
      expect(described_class::DECISION_CACHE_KEY).to eq("llm/openrouter/decision_models/v1")
    end

    it "defines CACHE_TTL as 12 hours" do
      expect(described_class::CACHE_TTL).to eq(12.hours)
    end

    it "defines OPEN_TIMEOUT_SECONDS as 5" do
      expect(described_class::OPEN_TIMEOUT_SECONDS).to eq(5)
    end

    it "defines READ_TIMEOUT_SECONDS as 10" do
      expect(described_class::READ_TIMEOUT_SECONDS).to eq(10)
    end

    it "defines SLUG_PATTERN matching provider and model slugs" do
      expect(described_class::SLUG_PATTERN).to be_a(Regexp)
    end
  end

  describe ".valid_slug?" do
    it "returns true for standard provider/model identifiers" do
      expect(described_class.valid_slug?("openai/gpt-4o")).to be true
      expect(described_class.valid_slug?("anthropic/claude-3.5-sonnet")).to be true
    end

    it "returns true for provider names with dots, underscores, and hyphens" do
      expect(described_class.valid_slug?("meta-llama/llama-3.3-70b-instruct")).to be true
      expect(described_class.valid_slug?("mistralai/mistral-large-2411")).to be true
      expect(described_class.valid_slug?("foo_bar.baz/model-one")).to be true
    end

    it "returns true for OpenRouter Latest alias syntax with leading tilde" do
      expect(described_class.valid_slug?("~deepseek/deepseek-pro-latest")).to be true
      expect(described_class.valid_slug?("~openai/gpt-4o-latest")).to be true
    end

    it "returns true for colon variant suffixes" do
      expect(described_class.valid_slug?("google/gemini-2.5-flash:free")).to be true
      expect(described_class.valid_slug?("openai/gpt-4o:extended")).to be true
    end

    it "returns true for symbols and values with surrounding whitespace" do
      expect(described_class.valid_slug?(:"openai/gpt-4o")).to be true
      expect(described_class.valid_slug?("  openai/gpt-4o \n")).to be true
    end

    it "returns false for model IDs without a provider or forward slash" do
      expect(described_class.valid_slug?("gpt-4o")).to be false
      expect(described_class.valid_slug?("claude-3-5-sonnet")).to be false
    end

    it "returns false for blank or empty inputs" do
      expect(described_class.valid_slug?("")).to be false
      expect(described_class.valid_slug?("   ")).to be false
      expect(described_class.valid_slug?(nil)).to be false
    end

    it "returns false for slugs with missing parts" do
      expect(described_class.valid_slug?("openai/")).to be false
      expect(described_class.valid_slug?("/gpt-4o")).to be false
      expect(described_class.valid_slug?("~")).to be false
      expect(described_class.valid_slug?("~/gpt-4o")).to be false
    end

    it "returns false for multiple slashes, wildcards, or invalid characters" do
      expect(described_class.valid_slug?("openai/org/model")).to be false
      expect(described_class.valid_slug?("openai/*")).to be false
      expect(described_class.valid_slug?("*/gpt-4o")).to be false
      expect(described_class.valid_slug?("openai/gpt 4o")).to be false
    end

    it "rejects malformed model slug formats" do
      invalid_slugs = [
        "bad slug with spaces",
        "foo/bar/baz",
        "foo/bar/baz/qux",
        "foo//bar",
        "/leading-slash",
        "trailing-slash/",
        "no-slash-at-all",
        "openai/*",
        "model:without-slash",
        "foo\\bar",
        "foo@bar/baz",
        "foo/bar?baz=1",
        "foo/bar#fragment",
        "~",
        "~/invalid",
        "~foo//bar",
        "..",
        "../etc/passwd",
        "foo/bar\x00nullbyte"
      ]

      invalid_slugs.each do |slug|
        expect(described_class.valid_slug?(slug)).to be(false), "Expected slug #{slug.inspect} to be rejected"
      end
    end

    it "rejects single-slash path traversal and dot-segment identifiers" do
      traversal_slugs = [
        "../passwd",
        "./something",
        "vendor/..",
        "vendor/.",
        "../..",
        "./.",
        "~../foo",
        "~./foo",
        ".../model",
        "vendor/...",
        "vendor/..passwd",
        "vendor/foo..bar",
        "vendor/foo.."
      ]

      traversal_slugs.each do |slug|
        expect(described_class.valid_slug?(slug)).to be(false), "Expected traversal slug #{slug.inspect} to be rejected"
      end
    end

    it "accepts valid complex slug formats" do
      valid_slugs = [
        "scaledown/classify-1",
        "~typesafe/jev-latest",
        "~perplexity/pplx-decider-latest",
        "~perplexity/pplx-decider-flash-latest",
        "vendor-1.0_preview/model-name.2026:instruct",
        "~org.sub_domain/model.v1-rc_2:8b",
        "a/b"
      ]

      valid_slugs.each do |slug|
        expect(described_class.valid_slug?(slug)).to be(true), "Expected slug #{slug.inspect} to be accepted"
      end
    end

    it "handles whitespace stripping and non-string values during slug validation" do
      expect(described_class.valid_slug?("  scaledown/classify-1 \n\t ")).to be true
      expect(described_class.valid_slug?("   ")).to be false
      expect(described_class.valid_slug?(nil)).to be false
      expect(described_class.valid_slug?(123)).to be false
    end
  end

  describe ".call" do
    context "when upstream request succeeds" do
      before do
        stub_request(:get, described_class::MODELS_ENDPOINT)
          .with(headers: {"Accept" => "application/json"})
          .to_return(status: 200, body: @raw_response_body, headers: {"Content-Type" => "application/json"})
      end

      it "fetches from OpenRouter and normalizes structured-output models" do
        models = described_class.call

        expect(models).to be_an(Array)
        expect(models.size).to eq(4)
        expect(models).to be_frozen

        models.each do |model|
          expect(model).to be_a(Hash)
          expect(model).to be_frozen
          expect(model.keys).to contain_exactly(:id, :label, :supports_reasoning)
        end
      end

      it "sorts models alphabetically by label (case-insensitive)" do
        models = described_class.call
        labels = models.pluck(:label)

        expect(labels).to eq([
          "Anthropic: Claude 3.7 Sonnet",
          "DeepSeek: R1",
          "meta-llama/llama-3.3-70b-instruct",
          "OpenAI: GPT-4o-mini"
        ])
      end

      it "falls back to model id when name is blank or missing" do
        models = described_class.call
        llama = models.find { |m| m[:id] == "meta-llama/llama-3.3-70b-instruct" }

        expect(llama[:label]).to eq("meta-llama/llama-3.3-70b-instruct")
      end

      it "includes Authorization header when OPENROUTER_API_KEY is present" do
        allow(EnvSecret).to receive(:read).with("OPENROUTER_API_KEY").and_return("sk-or-v1-secret")

        auth_stub = stub_request(:get, described_class::MODELS_ENDPOINT)
          .with(headers: {"Accept" => "application/json", "Authorization" => "Bearer sk-or-v1-secret"})
          .to_return(status: 200, body: @raw_response_body, headers: {"Content-Type" => "application/json"})

        described_class.call(force_refresh: true)

        expect(auth_stub).to have_been_requested
      end

      it "includes Authorization header when OPEN_ROUTER_API_KEY is present" do
        allow(EnvSecret).to receive(:read).with("OPEN_ROUTER_API_KEY").and_return("sk-or-v1-alt-secret")

        auth_stub = stub_request(:get, described_class::MODELS_ENDPOINT)
          .with(headers: {"Accept" => "application/json", "Authorization" => "Bearer sk-or-v1-alt-secret"})
          .to_return(status: 200, body: @raw_response_body, headers: {"Content-Type" => "application/json"})

        described_class.call(force_refresh: true)

        expect(auth_stub).to have_been_requested
      end

      describe "reasoning support detection" do
        it "detects supports_reasoning from reasoning.supported_efforts array" do
          models = described_class.call
          r1 = models.find { |m| m[:id] == "deepseek/deepseek-r1" }
          mini = models.find { |m| m[:id] == "openai/gpt-4o-mini" }

          expect(r1[:supports_reasoning]).to be true
          expect(mini[:supports_reasoning]).to be false
        end

        it "detects supports_reasoning from supported_parameters containing reasoning or reasoning_effort" do
          models = described_class.call
          sonnet = models.find { |m| m[:id] == "anthropic/claude-3.7-sonnet" }

          expect(sonnet[:supports_reasoning]).to be true
        end
      end

      describe "deduplication" do
        it "deduplicates entries by id, preserving the first seen" do
          duplicate_data = [
            {
              "id" => "deepseek/deepseek-chat",
              "name" => "First DeepSeek Chat",
              "supported_parameters" => ["structured_outputs"]
            },
            {
              "id" => "deepseek/deepseek-chat",
              "name" => "Duplicate DeepSeek Chat",
              "supported_parameters" => ["structured_outputs"]
            }
          ]
          stub_request(:get, described_class::MODELS_ENDPOINT)
            .with(headers: {"Accept" => "application/json"})
            .to_return(status: 200, body: {"data" => duplicate_data}.to_json, headers: {"Content-Type" => "application/json"})

          models = described_class.call(force_refresh: true)

          expect(models.size).to eq(1)
          expect(models.first[:label]).to eq("First DeepSeek Chat")
        end
      end

      describe "filtering invalid items" do
        it "filters out non-hashes, missing ids, invalid slugs, and models without structured_outputs" do
          mixed_data = [
            "not a hash",
            123,
            nil,
            {"id" => nil, "name" => "Missing ID", "supported_parameters" => ["structured_outputs"]},
            {"id" => "", "name" => "Empty ID", "supported_parameters" => ["structured_outputs"]},
            {"id" => "   ", "name" => "Whitespace ID", "supported_parameters" => ["structured_outputs"]},
            {"id" => "no-slash-slug", "name" => "Invalid Slug", "supported_parameters" => ["structured_outputs"]},
            {"id" => "openai/*", "name" => "Wildcard Slug", "supported_parameters" => ["structured_outputs"]},
            {
              "id" => "vendor/no-structured-outputs",
              "name" => "Omits Structured Outputs",
              "supported_parameters" => ["tools", "json_mode"]
            },
            {
              "id" => "valid/supported-model",
              "name" => "Valid Model",
              "supported_parameters" => ["structured_outputs"]
            }
          ]
          stub_request(:get, described_class::MODELS_ENDPOINT)
            .with(headers: {"Accept" => "application/json"})
            .to_return(status: 200, body: {"data" => mixed_data}.to_json, headers: {"Content-Type" => "application/json"})

          models = described_class.call(force_refresh: true)

          expect(models.pluck(:id)).to eq(["valid/supported-model"])
        end
      end
    end

    context "caching behavior" do
      it "caches successful responses in Rails.cache under CACHE_KEY for 12 hours" do
        api_stub = stub_request(:get, described_class::MODELS_ENDPOINT)
          .to_return(status: 200, body: @raw_response_body, headers: {"Content-Type" => "application/json"})

        expect(Rails.cache.exist?(described_class::CACHE_KEY)).to be false

        first_call = described_class.call

        expect(api_stub).to have_been_requested.once
        expect(Rails.cache.exist?(described_class::CACHE_KEY)).to be true
        expect(Rails.cache.read(described_class::CACHE_KEY)).to eq(first_call)

        second_call = described_class.call

        expect(api_stub).to have_been_requested.once
        expect(second_call).to eq(first_call)
      end

      it "bypasses the cache and refreshes data when force_refresh: true is passed" do
        stub_request(:get, described_class::MODELS_ENDPOINT)
          .to_return(status: 200, body: @raw_response_body, headers: {"Content-Type" => "application/json"})

        described_class.call

        updated_data = [
          {
            "id" => "new-provider/new-model",
            "name" => "Brand New Model",
            "supported_parameters" => ["structured_outputs"]
          }
        ]
        stub_request(:get, described_class::MODELS_ENDPOINT)
          .to_return(status: 200, body: {"data" => updated_data}.to_json, headers: {"Content-Type" => "application/json"})

        second_call = described_class.call(force_refresh: true)

        expect(second_call.pluck(:id)).to eq(["new-provider/new-model"])
        expect(Rails.cache.read(described_class::CACHE_KEY)).to eq(second_call)

        third_call = described_class.call
        expect(third_call.pluck(:id)).to eq(["new-provider/new-model"])
      end
    end

    context "error handling and resilience" do
      before do
        allow(Rails.logger).to receive(:warn)
      end

      context "when cache is cold" do
        it "returns empty array on HTTP 500 without caching the failure" do
          stub_request(:get, described_class::MODELS_ENDPOINT).to_return(status: 500, body: "Internal Server Error")

          models = described_class.call

          expect(models).to eq([])
          expect(Rails.logger).to have_received(:warn).with(/Llm::OpenRouterModelsService failed to fetch models:/)
          expect(Rails.cache.exist?(described_class::CACHE_KEY)).to be false

          stub_request(:get, described_class::MODELS_ENDPOINT).to_return(status: 200, body: @raw_response_body, headers: {"Content-Type" => "application/json"})
          expect(described_class.call.size).to eq(4)
        end

        it "returns empty array on Faraday::TimeoutError without raising" do
          stub_request(:get, described_class::MODELS_ENDPOINT).to_raise(Faraday::TimeoutError.new("execution expired"))

          models = described_class.call

          expect(models).to eq([])
          expect(Rails.logger).to have_received(:warn).with(/Faraday::TimeoutError/)
          expect(Rails.cache.exist?(described_class::CACHE_KEY)).to be false
        end

        it "returns empty array on Faraday::ConnectionFailed without raising" do
          stub_request(:get, described_class::MODELS_ENDPOINT).to_raise(Faraday::ConnectionFailed.new("connection refused"))

          models = described_class.call

          expect(models).to eq([])
          expect(Rails.logger).to have_received(:warn).with(/Faraday::ConnectionFailed/)
          expect(Rails.cache.exist?(described_class::CACHE_KEY)).to be false
        end

        it "returns empty array on JSON::ParserError without raising" do
          stub_request(:get, described_class::MODELS_ENDPOINT).to_return(status: 200, body: "<html>Bad Gateway</html>")

          models = described_class.call

          expect(models).to eq([])
          expect(Rails.logger).to have_received(:warn).with(/JSON::ParserError/)
          expect(Rails.cache.exist?(described_class::CACHE_KEY)).to be false
        end
      end

      context "when stale cache is available" do
        before do
          Rails.cache.write(described_class::CACHE_KEY, @cached_models, expires_in: 12.hours)
        end

        it "returns stale cache on HTTP 500 during force_refresh" do
          stub_request(:get, described_class::MODELS_ENDPOINT).to_return(status: 500, body: "Server Error")

          models = described_class.call(force_refresh: true)

          expect(models).to eq(@cached_models)
          expect(Rails.logger).to have_received(:warn).with(/Llm::OpenRouterModelsService failed to fetch models:/)
          expect(Rails.cache.read(described_class::CACHE_KEY)).to eq(@cached_models)
        end

        it "returns stale cache on timeout during force_refresh" do
          stub_request(:get, described_class::MODELS_ENDPOINT).to_raise(Faraday::TimeoutError.new("timeout"))

          models = described_class.call(force_refresh: true)

          expect(models).to eq(@cached_models)
          expect(Rails.logger).to have_received(:warn).with(/Faraday::TimeoutError/)
          expect(Rails.cache.read(described_class::CACHE_KEY)).to eq(@cached_models)
        end

        it "returns stale cache on malformed JSON during force_refresh" do
          stub_request(:get, described_class::MODELS_ENDPOINT).to_return(status: 200, body: "not json")

          models = described_class.call(force_refresh: true)

          expect(models).to eq(@cached_models)
          expect(Rails.logger).to have_received(:warn).with(/JSON::ParserError/)
          expect(Rails.cache.read(described_class::CACHE_KEY)).to eq(@cached_models)
        end
      end
    end
  end

  describe ".lookup" do
    before do
      stub_request(:get, described_class::MODELS_ENDPOINT)
        .to_return(status: 200, body: @raw_response_body, headers: {"Content-Type" => "application/json"})
    end

    it "finds model by string ID" do
      result = described_class.lookup("deepseek/deepseek-r1")

      expect(result).to eq({
        id: "deepseek/deepseek-r1",
        label: "DeepSeek: R1",
        supports_reasoning: true
      })
    end

    it "finds model by symbol ID" do
      result = described_class.lookup(:"deepseek/deepseek-r1")

      expect(result).to eq({
        id: "deepseek/deepseek-r1",
        label: "DeepSeek: R1",
        supports_reasoning: true
      })
    end

    it "strips whitespace around model ID" do
      result = described_class.lookup("  deepseek/deepseek-r1 \n")

      expect(result).to eq({
        id: "deepseek/deepseek-r1",
        label: "DeepSeek: R1",
        supports_reasoning: true
      })
    end

    it "returns nil for nonexistent model ID" do
      expect(described_class.lookup("unknown/model")).to be_nil
    end

    it "returns nil for blank or nil ID" do
      expect(described_class.lookup("")).to be_nil
      expect(described_class.lookup("   ")).to be_nil
      expect(described_class.lookup(nil)).to be_nil
    end
  end

  describe ".decision_models" do
    context "when upstream request succeeds" do
      before do
        stub_request(:get, described_class::DECISION_MODELS_ENDPOINT)
          .with(headers: {"Accept" => "application/json"})
          .to_return(status: 200, body: @raw_decision_response_body, headers: {"Content-Type" => "application/json"})
      end

      it "fetches from OpenRouter and normalizes decision models" do
        models = described_class.decision_models

        expect(models).to be_an(Array)
        expect(models.size).to eq(4)
        expect(models).to be_frozen

        models.each do |model|
          expect(model).to be_a(Hash)
          expect(model).to be_frozen
          expect(model.keys).to contain_exactly(:id, :label, :supports_reasoning, :mode)
          expect(model[:supports_reasoning]).to be false
          expect(model[:mode]).to eq(:decision)
        end
      end

      it "sorts decision models alphabetically by label (case-insensitive)" do
        models = described_class.decision_models
        labels = models.pluck(:label)

        expect(labels).to eq([
          "Jev Latest",
          "Perplexity Decider Latest",
          "ScaleDown: Classify",
          "~perplexity/pplx-decider-flash-latest"
        ])
      end

      it "falls back to model id when name is blank or missing" do
        models = described_class.decision_models
        flash = models.find { |m| m[:id] == "~perplexity/pplx-decider-flash-latest" }

        expect(flash[:label]).to eq("~perplexity/pplx-decider-flash-latest")
      end

      it "includes Authorization header when OPENROUTER_API_KEY is present" do
        allow(EnvSecret).to receive(:read).with("OPENROUTER_API_KEY").and_return("sk-or-v1-secret")

        auth_stub = stub_request(:get, described_class::DECISION_MODELS_ENDPOINT)
          .with(headers: {"Accept" => "application/json", "Authorization" => "Bearer sk-or-v1-secret"})
          .to_return(status: 200, body: @raw_decision_response_body, headers: {"Content-Type" => "application/json"})

        described_class.decision_models(force_refresh: true)

        expect(auth_stub).to have_been_requested
      end

      describe "deduplication" do
        it "deduplicates entries by id, preserving the first seen" do
          duplicate_data = [
            {
              "id" => "scaledown/classify-1",
              "name" => "First Classify",
              "architecture" => {"output_modalities" => ["decisions"]}
            },
            {
              "id" => "scaledown/classify-1",
              "name" => "Duplicate Classify",
              "architecture" => {"output_modalities" => ["decisions"]}
            }
          ]
          stub_request(:get, described_class::DECISION_MODELS_ENDPOINT)
            .with(headers: {"Accept" => "application/json"})
            .to_return(status: 200, body: {"data" => duplicate_data}.to_json, headers: {"Content-Type" => "application/json"})

          models = described_class.decision_models(force_refresh: true)

          expect(models.size).to eq(1)
          expect(models.first[:label]).to eq("First Classify")
        end

        it "sorts models case-insensitively by label with tie-breaking by id" do
          mixed_sort_payload = [
            {"id" => "vendor/z-model", "name" => "zebra", "architecture" => {"output_modalities" => ["decisions"]}},
            {"id" => "vendor/a-model", "name" => "Alpha", "architecture" => {"output_modalities" => ["decisions"]}},
            {"id" => "vendor/b-model-2", "name" => "BETA", "architecture" => {"output_modalities" => ["decisions"]}},
            {"id" => "vendor/b-model-1", "name" => "beta", "architecture" => {"output_modalities" => ["decisions"]}},
            {"id" => "vendor/c-model", "name" => "", "architecture" => {"output_modalities" => ["decisions"]}}
          ]

          stub_request(:get, described_class::DECISION_MODELS_ENDPOINT)
            .with(headers: {"Accept" => "application/json"})
            .to_return(status: 200, body: {"data" => mixed_sort_payload}.to_json, headers: {"Content-Type" => "application/json"})

          result = described_class.decision_models(force_refresh: true)

          labels = result.pluck(:label)
          expect(labels).to eq(["Alpha", "beta", "BETA", "vendor/c-model", "zebra"])
          beta_ids = result.select { |m| m[:label].casecmp?("beta") }.pluck(:id)
          expect(beta_ids).to eq(["vendor/b-model-1", "vendor/b-model-2"])
        end

        it "strictly freezes the returned Array and every Hash element within it" do
          valid_payload = [
            {"id" => "scaledown/classify-1", "name" => "ScaleDown", "architecture" => {"output_modalities" => ["decisions"]}},
            {"id" => "~typesafe/jev-latest", "name" => "Jev", "architecture" => {"output_modalities" => ["decisions"]}}
          ]

          stub_request(:get, described_class::DECISION_MODELS_ENDPOINT)
            .with(headers: {"Accept" => "application/json"})
            .to_return(status: 200, body: {"data" => valid_payload}.to_json, headers: {"Content-Type" => "application/json"})

          result = described_class.decision_models(force_refresh: true)

          expect(result).to be_frozen
          result.each do |model|
            expect(model).to be_frozen
            expect { model[:id] = "mutated" }.to raise_error(FrozenError)
            expect { model[:label] = "mutated" }.to raise_error(FrozenError)
            expect { model[:mode] = :chat }.to raise_error(FrozenError)
          end
          expect { result << {id: "extra"} }.to raise_error(FrozenError)
        end
      end

      describe "filtering invalid items" do
        it "filters out non-hashes, missing ids, invalid slugs, and models without decisions modality" do
          mixed_data = [
            "not a hash",
            123,
            nil,
            {"id" => nil, "name" => "Missing ID", "architecture" => {"output_modalities" => ["decisions"]}},
            {"id" => "", "name" => "Empty ID", "architecture" => {"output_modalities" => ["decisions"]}},
            {"id" => "   ", "name" => "Whitespace ID", "architecture" => {"output_modalities" => ["decisions"]}},
            {"id" => "no-slash-slug", "name" => "Invalid Slug", "architecture" => {"output_modalities" => ["decisions"]}},
            {"id" => "openai/*", "name" => "Wildcard Slug", "architecture" => {"output_modalities" => ["decisions"]}},
            {"id" => "../passwd", "name" => "Traversal Slug", "architecture" => {"output_modalities" => ["decisions"]}},
            {"id" => "vendor/..", "name" => "Parent Traversal Slug", "architecture" => {"output_modalities" => ["decisions"]}},
            {
              "id" => "vendor/chat-only",
              "name" => "Chat Only Model",
              "architecture" => {"output_modalities" => ["text"]}
            },
            {
              "id" => "vendor/non-array-modality",
              "name" => "Invalid Modality Type",
              "architecture" => {"output_modalities" => "decisions"}
            },
            {
              "id" => "vendor/empty-arch",
              "name" => "Empty Arch",
              "architecture" => {}
            },
            {
              "id" => "vendor/string-arch",
              "name" => "String Architecture",
              "architecture" => "text->text"
            },
            {
              "id" => "vendor/array-arch",
              "name" => "Array Architecture",
              "architecture" => ["text"]
            },
            {
              "id" => "vendor/missing-modalities",
              "name" => "Missing Modalities",
              "architecture" => {"tokenizer" => "Claude"}
            },
            {
              "id" => "nil-arch/decision-model",
              "name" => "Nil Architecture Decision Model",
              "architecture" => nil
            },
            {
              "id" => "minimal/decision-model",
              "name" => "Minimal Payload Decision Model"
            },
            {
              "id" => "valid/decision-model",
              "name" => "Valid Model",
              "architecture" => {"output_modalities" => ["decisions"]}
            }
          ]
          stub_request(:get, described_class::DECISION_MODELS_ENDPOINT)
            .with(headers: {"Accept" => "application/json"})
            .to_return(status: 200, body: {"data" => mixed_data}.to_json, headers: {"Content-Type" => "application/json"})

          models = described_class.decision_models(force_refresh: true)

          expect(models.pluck(:id)).to contain_exactly(
            "minimal/decision-model",
            "nil-arch/decision-model",
            "valid/decision-model"
          )
        end

        it "filters out models with non-decision output modalities" do
          non_decision_payload = [
            {
              "id" => "vendor/text-only",
              "name" => "Text Only",
              "architecture" => {"output_modalities" => ["text"]}
            },
            {
              "id" => "vendor/image-only",
              "name" => "Image Only",
              "architecture" => {"output_modalities" => ["image"]}
            },
            {
              "id" => "vendor/audio-and-text",
              "name" => "Audio and Text",
              "architecture" => {"output_modalities" => ["audio", "text"]}
            },
            {
              "id" => "vendor/empty-modalities",
              "name" => "Empty Modalities",
              "architecture" => {"output_modalities" => []}
            },
            {
              "id" => "vendor/string-modality",
              "name" => "String Modality",
              "architecture" => {"output_modalities" => "decisions"}
            },
            {
              "id" => "vendor/nil-modalities",
              "name" => "Nil Modalities",
              "architecture" => {"output_modalities" => nil}
            },
            {
              "id" => "vendor/uppercase-decisions",
              "name" => "Uppercase Decisions",
              "architecture" => {"output_modalities" => ["DECISIONS"]}
            },
            {
              "id" => "vendor/mixed-valid",
              "name" => "Mixed Valid",
              "architecture" => {"output_modalities" => ["text", "decisions", "embeddings"]}
            }
          ]

          stub_request(:get, described_class::DECISION_MODELS_ENDPOINT)
            .with(headers: {"Accept" => "application/json"})
            .to_return(status: 200, body: {"data" => non_decision_payload}.to_json, headers: {"Content-Type" => "application/json"})

          result = described_class.decision_models(force_refresh: true)

          expect(result.pluck(:id)).to eq(["vendor/mixed-valid"])
        end

        it "filters out non-hash and corrupt items in the data array" do
          corrupt_data = [
            nil,
            false,
            true,
            12345,
            3.14159,
            "a string item",
            [],
            ["nested", "array"],
            {"id" => nil},
            {"id" => 123},
            {"id" => {}},
            {"id" => []},
            {"id" => ""},
            {"id" => "   \t\n  "},
            {
              "id" => "valid/model-1",
              "name" => "Valid Model 1",
              "architecture" => {"output_modalities" => ["decisions"]}
            }
          ]

          stub_request(:get, described_class::DECISION_MODELS_ENDPOINT)
            .with(headers: {"Accept" => "application/json"})
            .to_return(status: 200, body: {"data" => corrupt_data}.to_json, headers: {"Content-Type" => "application/json"})

          result = described_class.decision_models(force_refresh: true)

          expect(result.size).to eq(1)
          expect(result.first[:id]).to eq("valid/model-1")
          expect(result.first[:label]).to eq("Valid Model 1")
          expect(result.first[:mode]).to eq(:decision)
          expect(result.first[:supports_reasoning]).to be false
        end
      end
    end

    context "caching behavior" do
      it "caches successful responses in Rails.cache under DECISION_CACHE_KEY for 12 hours" do
        api_stub = stub_request(:get, described_class::DECISION_MODELS_ENDPOINT)
          .to_return(status: 200, body: @raw_decision_response_body, headers: {"Content-Type" => "application/json"})

        expect(Rails.cache.exist?(described_class::DECISION_CACHE_KEY)).to be false

        first_call = described_class.decision_models

        expect(api_stub).to have_been_requested.once
        expect(Rails.cache.exist?(described_class::DECISION_CACHE_KEY)).to be true
        expect(Rails.cache.read(described_class::DECISION_CACHE_KEY)).to eq(first_call)

        second_call = described_class.decision_models

        expect(api_stub).to have_been_requested.once
        expect(second_call).to eq(first_call)
      end

      it "bypasses the cache and refreshes data when force_refresh: true is passed" do
        stub_request(:get, described_class::DECISION_MODELS_ENDPOINT)
          .to_return(status: 200, body: @raw_decision_response_body, headers: {"Content-Type" => "application/json"})

        described_class.decision_models

        updated_data = [
          {
            "id" => "new-provider/new-decider",
            "name" => "Brand New Decider",
            "architecture" => {"output_modalities" => ["decisions"]}
          }
        ]
        stub_request(:get, described_class::DECISION_MODELS_ENDPOINT)
          .to_return(status: 200, body: {"data" => updated_data}.to_json, headers: {"Content-Type" => "application/json"})

        second_call = described_class.decision_models(force_refresh: true)

        expect(second_call.pluck(:id)).to eq(["new-provider/new-decider"])
        expect(Rails.cache.read(described_class::DECISION_CACHE_KEY)).to eq(second_call)

        third_call = described_class.decision_models
        expect(third_call.pluck(:id)).to eq(["new-provider/new-decider"])
      end
    end

    context "error handling and resilience" do
      before do
        allow(Rails.logger).to receive(:warn)
      end

      context "when cache is cold" do
        it "returns empty array on HTTP 500 without caching the failure" do
          stub_request(:get, described_class::DECISION_MODELS_ENDPOINT).to_return(status: 500, body: "Internal Server Error")

          models = described_class.decision_models

          expect(models).to eq([])
          expect(Rails.logger).to have_received(:warn).with(/Llm::OpenRouterModelsService failed to fetch models:/)
          expect(Rails.cache.exist?(described_class::DECISION_CACHE_KEY)).to be false

          stub_request(:get, described_class::DECISION_MODELS_ENDPOINT).to_return(status: 200, body: @raw_decision_response_body, headers: {"Content-Type" => "application/json"})
          expect(described_class.decision_models.size).to eq(4)
        end

        it "returns empty array on Faraday::TimeoutError without raising" do
          stub_request(:get, described_class::DECISION_MODELS_ENDPOINT).to_raise(Faraday::TimeoutError.new("execution expired"))

          models = described_class.decision_models

          expect(models).to eq([])
          expect(Rails.logger).to have_received(:warn).with(/Faraday::TimeoutError/)
          expect(Rails.cache.exist?(described_class::DECISION_CACHE_KEY)).to be false
        end

        it "returns empty array on Faraday::ConnectionFailed without raising" do
          stub_request(:get, described_class::DECISION_MODELS_ENDPOINT).to_raise(Faraday::ConnectionFailed.new("connection refused"))

          models = described_class.decision_models

          expect(models).to eq([])
          expect(Rails.logger).to have_received(:warn).with(/Faraday::ConnectionFailed/)
          expect(Rails.cache.exist?(described_class::DECISION_CACHE_KEY)).to be false
        end

        it "returns empty array on JSON::ParserError without raising" do
          stub_request(:get, described_class::DECISION_MODELS_ENDPOINT).to_return(status: 200, body: "<html>Bad Gateway</html>")

          models = described_class.decision_models

          expect(models).to eq([])
          expect(Rails.logger).to have_received(:warn).with(/JSON::ParserError/)
          expect(Rails.cache.exist?(described_class::DECISION_CACHE_KEY)).to be false
        end

        it "handles non-JSON raw response bodies without raising" do
          hostile_bodies = [
            "<html>502 Bad Gateway</html>",
            "<?xml version=\"1.0\"?><error>Service Unavailable</error>",
            "",
            "    ",
            "null",
            "12345",
            "true",
            "false",
            "undefined",
            "[1, 2, 3]",
            "{\"data\": "
          ]

          hostile_bodies.each do |body|
            stub_request(:get, described_class::DECISION_MODELS_ENDPOINT).to_return(status: 200, body: body)

            result = described_class.decision_models(force_refresh: true)

            expect(result).to eq([])
            expect(result).to be_frozen
            expect(Rails.cache.exist?(described_class::DECISION_CACHE_KEY)).to be false
          end
        end

        it "handles missing, nil, or non-array 'data' envelopes without raising" do
          malformed_envelopes = [
            {},
            {"models" => []},
            {"error" => {"message" => "Rate limit exceeded"}},
            {"data" => nil},
            {"data" => "not_an_array"},
            {"data" => 12345},
            {"data" => true},
            {"data" => {}}
          ]

          malformed_envelopes.each do |envelope|
            stub_request(:get, described_class::DECISION_MODELS_ENDPOINT).to_return(status: 200, body: envelope.to_json)

            result = described_class.decision_models(force_refresh: true)

            expect(result).to eq([])
            expect(result).to be_frozen
            expect(Rails.cache.exist?(described_class::DECISION_CACHE_KEY)).to be false
          end
        end

        it "returns empty array for all HTTP error status codes (400, 401, 403, 404, 429, 500, 502, 503, 504)" do
          status_codes = [400, 401, 403, 404, 429, 500, 502, 503, 504]
          status_codes.each do |status_code|
            stub_request(:get, described_class::DECISION_MODELS_ENDPOINT).to_return(status: status_code, body: "Error #{status_code}")

            result = described_class.decision_models(force_refresh: true)

            expect(result).to eq([])
            expect(result).to be_frozen
            expect(Rails.cache.exist?(described_class::DECISION_CACHE_KEY)).to be false
          end
        end

        it "returns empty array on Faraday::SSLError without raising" do
          stub_request(:get, described_class::DECISION_MODELS_ENDPOINT).to_raise(Faraday::SSLError.new("SSL handshake failed"))

          result = described_class.decision_models(force_refresh: true)

          expect(result).to eq([])
          expect(result).to be_frozen
          expect(Rails.cache.exist?(described_class::DECISION_CACHE_KEY)).to be false
          expect(Rails.logger).to have_received(:warn).with(/Faraday::SSLError/)
        end
      end

      context "when stale cache is available" do
        before do
          Rails.cache.write(described_class::DECISION_CACHE_KEY, @cached_decision_models, expires_in: 12.hours)
        end

        it "returns stale cache on HTTP 500 during force_refresh" do
          stub_request(:get, described_class::DECISION_MODELS_ENDPOINT).to_return(status: 500, body: "Server Error")

          models = described_class.decision_models(force_refresh: true)

          expect(models).to eq(@cached_decision_models)
          expect(Rails.logger).to have_received(:warn).with(/Llm::OpenRouterModelsService failed to fetch models:/)
          expect(Rails.cache.read(described_class::DECISION_CACHE_KEY)).to eq(@cached_decision_models)
        end

        it "preserves and returns stale cache on HTTP 429 rate limit during force_refresh" do
          stub_request(:get, described_class::DECISION_MODELS_ENDPOINT).to_return(status: 429, body: "Rate limited")

          result = described_class.decision_models(force_refresh: true)

          expect(result).to eq(@cached_decision_models)
          expect(Rails.cache.read(described_class::DECISION_CACHE_KEY)).to eq(@cached_decision_models)
        end

        it "returns stale cache on timeout during force_refresh" do
          stub_request(:get, described_class::DECISION_MODELS_ENDPOINT).to_raise(Faraday::TimeoutError.new("timeout"))

          models = described_class.decision_models(force_refresh: true)

          expect(models).to eq(@cached_decision_models)
          expect(Rails.logger).to have_received(:warn).with(/Faraday::TimeoutError/)
          expect(Rails.cache.read(described_class::DECISION_CACHE_KEY)).to eq(@cached_decision_models)
        end

        it "returns stale cache on malformed JSON during force_refresh" do
          stub_request(:get, described_class::DECISION_MODELS_ENDPOINT).to_return(status: 200, body: "not json")

          models = described_class.decision_models(force_refresh: true)

          expect(models).to eq(@cached_decision_models)
          expect(Rails.logger).to have_received(:warn).with(/JSON::ParserError/)
          expect(Rails.cache.read(described_class::DECISION_CACHE_KEY)).to eq(@cached_decision_models)
        end
      end

      describe "cache key isolation" do
        it "isolates decision cache key from chat cache key" do
          stub_request(:get, described_class::DECISION_MODELS_ENDPOINT)
            .to_return(status: 200, body: @raw_decision_response_body, headers: {"Content-Type" => "application/json"})

          expect(Rails.cache.exist?(described_class::DECISION_CACHE_KEY)).to be false
          expect(Rails.cache.exist?(described_class::CACHE_KEY)).to be false

          described_class.decision_models(force_refresh: true)

          expect(Rails.cache.exist?(described_class::DECISION_CACHE_KEY)).to be true
          expect(Rails.cache.exist?(described_class::CACHE_KEY)).to be false
        end
      end
    end
  end

  describe ".lookup_decision_model" do
    before do
      stub_request(:get, described_class::DECISION_MODELS_ENDPOINT)
        .to_return(status: 200, body: @raw_decision_response_body, headers: {"Content-Type" => "application/json"})
    end

    it "finds decision model by string ID" do
      result = described_class.lookup_decision_model("scaledown/classify-1")

      expect(result).to eq({
        id: "scaledown/classify-1",
        label: "ScaleDown: Classify",
        supports_reasoning: false,
        mode: :decision
      })
    end

    it "finds decision model by symbol ID" do
      result = described_class.lookup_decision_model(:"~typesafe/jev-latest")

      expect(result).to eq({
        id: "~typesafe/jev-latest",
        label: "Jev Latest",
        supports_reasoning: false,
        mode: :decision
      })
    end

    it "strips whitespace around decision model ID" do
      result = described_class.lookup_decision_model("  scaledown/classify-1 \n")

      expect(result).to eq({
        id: "scaledown/classify-1",
        label: "ScaleDown: Classify",
        supports_reasoning: false,
        mode: :decision
      })
    end

    it "returns nil for nonexistent decision model ID" do
      expect(described_class.lookup_decision_model("unknown/model")).to be_nil
    end

    it "returns nil for blank or nil ID" do
      expect(described_class.lookup_decision_model("")).to be_nil
      expect(described_class.lookup_decision_model("   ")).to be_nil
      expect(described_class.lookup_decision_model(nil)).to be_nil
    end

    it "searches a passed models collection without calling .decision_models" do
      custom_models = [
        {id: "custom/decision-1", label: "Custom 1", supports_reasoning: false, mode: :decision}.freeze
      ].freeze

      result = described_class.lookup_decision_model("custom/decision-1", models: custom_models)

      expect(result).to eq(custom_models.first)
    end

    it "handles custom models collection when model is not found" do
      custom_models = [
        {id: "override/decider", label: "Custom Override", supports_reasoning: false, mode: :decision}.freeze
      ].freeze

      expect(described_class.lookup_decision_model("scaledown/classify-1", models: custom_models)).to be_nil
    end
  end

  describe "ModelCatalog integration" do
    it "resolves built-in decision routes with mode :decision and supports_reasoning: false" do
      builtin_decision_keys = [
        "ScaleDown Classify Latest",
        "scaledown/classify-1",
        "Jev Latest",
        "~typesafe/jev-latest",
        "Perplexity Decider Latest",
        "~perplexity/pplx-decider-latest",
        "Perplexity Decider Flash Latest",
        "~perplexity/pplx-decider-flash-latest"
      ]

      builtin_decision_keys.each do |key|
        route = Llm::ModelCatalog.lookup(key)
        expect(route).not_to be_nil
        next unless route

        expect(route.mode).to eq(:decision)
        expect(route.decision_model?).to be true
        expect(route.extraction_model?).to be false
        expect(route.supports_reasoning?).to be false
        expect(route.supports_reasoning).to be false
      end
    end

    it "resolves built-in extraction route with mode :extraction" do
      ["ScaleDown Extract Latest", "scaledown/extract"].each do |key|
        route = Llm::ModelCatalog.lookup(key)
        expect(route).not_to be_nil
        next unless route

        expect(route.mode).to eq(:extraction)
        expect(route.decision_model?).to be false
        expect(route.extraction_model?).to be true
        expect(route.supports_reasoning?).to be false
      end
    end

    it "strictly separates OpenRouter catalog routes for chat, decision, and extraction" do
      chat_choices = Llm::ModelCatalog::OPENROUTER_ROUTES.values.map(&:label).uniq
      decision_choices = Llm::ModelCatalog::OPENROUTER_DECISION_ROUTES.values.map(&:label).uniq
      extraction_choices = Llm::ModelCatalog::OPENROUTER_EXTRACTION_ROUTES.values.map(&:label).uniq

      expect(chat_choices.size).to eq(9)
      expect(decision_choices.size).to eq(4)
      expect(extraction_choices.size).to eq(1)

      expect(chat_choices & decision_choices).to be_empty
      expect(chat_choices & extraction_choices).to be_empty
      expect(decision_choices & extraction_choices).to be_empty
    end

    it "resolves dynamic decision models from OpenRouterModelsService cache with mode: :decision" do
      dynamic_cached = [
        {
          id: "dynamic-org/dynamic-decider-1",
          label: "Dynamic Decider 1",
          supports_reasoning: false,
          mode: :decision
        }.freeze
      ].freeze
      Rails.cache.write(described_class::DECISION_CACHE_KEY, dynamic_cached, expires_in: 12.hours)

      route = Llm::ModelCatalog.lookup("dynamic-org/dynamic-decider-1")

      expect(route).not_to be_nil
      return unless route

      expect(route.provider).to eq(:openrouter)
      expect(route.api_model).to eq("dynamic-org/dynamic-decider-1")
      expect(route.label).to eq("Dynamic Decider 1")
      expect(route.mode).to eq(:decision)
      expect(route.decision_model?).to be true
      expect(route.supports_reasoning?).to be false
    end
  end
end
