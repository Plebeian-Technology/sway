# frozen_string_literal: true

require "rails_helper"

RSpec.describe Llm::OpenRouterAdapter do
  let(:prompt) do
    Llm::PromptPayload.new(
      system_prompt: "STABLE SYSTEM PROMPT",
      user_message: "PER-BILL USER MESSAGE"
    )
  end
  let(:model) { "~deepseek/deepseek-pro-latest" }
  let(:schema) { BILL_SUMMARY_SCHEMA_HASH }
  let(:openai_double) { instance_double(OpenAI::Client) }

  before do
    allow(OpenAI::Client).to receive(:new).and_return(openai_double)
    allow(EnvSecret).to receive(:read).with("OPENROUTER_API_KEY").and_return("sk-or-v1-test-key")
  end

  def chat_response(*_args, **kwargs)
    content = kwargs.fetch(:content)
    finish_reason = kwargs.fetch(:finish_reason, "stop")
    provider = kwargs.fetch(:provider, "DeepSeek")
    model_name = kwargs.fetch(:model_name, "~deepseek/deepseek-pro-latest")
    {
      "choices" => [
        {
          "message" => {"content" => content},
          "finish_reason" => finish_reason
        }
      ],
      "model" => model_name,
      "provider" => provider,
      "usage" => {
        "prompt_tokens" => 100,
        "completion_tokens" => 50,
        "total_tokens" => 150
      },
      "openrouter_metadata" => {
        "endpoints" => {
          "available" => [
            {"provider" => provider, "selected" => true}
          ]
        },
        "attempts" => [
          {"provider" => provider, "model" => model_name, "status" => 200}
        ]
      }
    }
  end

  def valid_payload_json
    {
      "summary_markdown" => "A substantive summary of the bill.",
      "full_breakdown_markdown" => "Detailed analysis of affected sections.",
      "draft_org_positions" => []
    }.to_json
  end

  # Shared structured-output adapter examples hooks
  def stub_adapter_body(body)
    allow(openai_double).to receive(:chat).and_return(chat_response(content: body))
  end

  def stub_adapter_truncated
    allow(openai_double).to receive(:chat)
      .and_return(chat_response(content: valid_payload_json, finish_reason: "length"))
  end

  def stub_adapter_transport
    allow(openai_double).to receive(:chat).and_raise(Faraday::ConnectionFailed.new("connection refused"))
  end

  def run_structured_call
    described_class.new.generate_bill_summary(prompt: prompt, model: model, schema: schema)
  end

  include_examples "an Llm structured-output adapter"

  describe "#provider_label" do
    it "returns 'openrouter'" do
      expect(described_class.new.provider_label).to eq("openrouter")
    end
  end

  describe ".request_timeout_seconds" do
    it "reads from Sway::Settings.llm.openrouter_request_timeout_seconds" do
      with_app_config(:llm, openrouter_request_timeout_seconds: 90) do
        expect(described_class.request_timeout_seconds).to eq(90)
      end
    end

    it "falls back to default 120 when non-positive" do
      with_app_config(:llm, openrouter_request_timeout_seconds: 0) do
        expect(described_class.request_timeout_seconds).to eq(120)
      end
    end
  end

  describe ".api_key" do
    it "reads OPENROUTER_API_KEY from EnvSecret" do
      expect(described_class.api_key).to eq("sk-or-v1-test-key")
    end

    it "falls back to OPEN_ROUTER_API_KEY when the canonical key is absent" do
      allow(EnvSecret).to receive(:read).with("OPENROUTER_API_KEY").and_return(nil)
      allow(EnvSecret).to receive(:read).with("OPEN_ROUTER_API_KEY").and_return("sk-or-v1-alias-key")

      expect(described_class.api_key).to eq("sk-or-v1-alias-key")
    end

    it "prefers OPENROUTER_API_KEY when both key spellings are present" do
      allow(EnvSecret).to receive(:read).with("OPEN_ROUTER_API_KEY").and_return("sk-or-v1-alias-key")

      expect(described_class.api_key).to eq("sk-or-v1-test-key")
    end

    it "raises Llm::TransportError when OPENROUTER_API_KEY is missing or blank" do
      allow(EnvSecret).to receive(:read).with("OPENROUTER_API_KEY").and_return(nil)
      allow(EnvSecret).to receive(:read).with("OPEN_ROUTER_API_KEY").and_return(nil)
      expect {
        described_class.api_key
      }.to raise_error(Llm::TransportError, /OPENROUTER_API_KEY or OPEN_ROUTER_API_KEY is not set/)
    end
  end

  describe "provider preferences in request payload" do
    it "enforces zero data collection and parameter support without upstream pinning" do
      expect(openai_double).to receive(:chat) do |parameters:|
        provider_block = parameters.dig(:parameters, :provider) || parameters[:provider]
        expect(provider_block).to eq(
          data_collection: "deny",
          require_parameters: true
        )
        chat_response(content: valid_payload_json)
      end

      described_class.new.generate_bill_summary(prompt: prompt, model: model, schema: schema)
    end

    it "applies the identical provider preferences across all candidate models including OpenRouter Auto" do
      candidate_models = [
        "~deepseek/deepseek-pro-latest",
        "~deepseek/deepseek-flash-latest",
        "openrouter/auto"
      ]

      candidate_models.each do |candidate|
        expect(openai_double).to receive(:chat) do |parameters:|
          provider_block = parameters.dig(:parameters, :provider) || parameters[:provider]
          expect(provider_block).to eq(
            data_collection: "deny",
            require_parameters: true
          )
          chat_response(content: valid_payload_json)
        end

        described_class.new.generate_bill_summary(prompt: prompt, model: candidate, schema: schema)
      end
    end
  end

  describe "strict schema format for OpenAI-compatible chat endpoints" do
    it "sends response_format json_schema with strict true and stripped schema" do
      expect(openai_double).to receive(:chat) do |parameters:|
        params = parameters.dig(:parameters) || parameters
        rf = params[:response_format]
        expect(rf[:type]).to eq("json_schema")
        expect(rf[:json_schema][:name]).to eq("bill_summary")
        expect(rf[:json_schema][:strict]).to be(true)
        schema_used = rf[:json_schema][:schema]
        expect(schema_used["additionalProperties"]).to be(false)
        expect(schema_used.to_s).not_to include("\"minLength\"")
        chat_response(content: valid_payload_json)
      end

      described_class.new.generate_bill_summary(prompt: prompt, model: model, schema: schema)
    end
  end

  describe "response verification and refusal of unpinned upstreams" do
    it "succeeds and logs when served by a pinned upstream company" do
      allow(openai_double).to receive(:chat).and_return(
        chat_response(content: valid_payload_json, provider: "Together")
      )

      expect(SwayLogging).to receive(:info).with(
        "openrouter.call.completed",
        hash_including(
          upstream_company: "Together",
          model: "~deepseek/deepseek-pro-latest"
        )
      )

      adapter = described_class.new
      result = adapter.generate_bill_summary(prompt: prompt, model: model, schema: schema)
      expect(result).to be_a(Hash)
      expect(adapter.last_upstream_company).to eq("Together")
    end

    it "retains verified response metadata when content validation fails" do
      allow(openai_double).to receive(:chat).and_return(
        chat_response(content: valid_payload_json, finish_reason: "length", provider: "Fireworks")
      )
      adapter = described_class.new

      expect {
        adapter.generate_bill_summary(prompt: prompt, model: model, schema: schema)
      }.to raise_error(Llm::SchemaError, /response truncated/)
      expect(adapter.last_upstream_company).to eq("Fireworks")
      expect(adapter.last_response).to be_present
      expect(adapter.last_usage).to be_present
    end

    it "does not label the requested alias as the served model when the response omits model identity" do
      response = chat_response(content: valid_payload_json, provider: "Together")
      response.delete("model")
      allow(openai_double).to receive(:chat).and_return(response)
      expect(SwayLogging).to receive(:info).with(
        "openrouter.call.completed",
        upstream_company: "Together",
        model: nil,
        requested_model: model
      )

      described_class.new.generate_bill_summary(prompt: prompt, model: model, schema: schema)
    end

    it "accepts any valid non-blank upstream company including Novita, Anthropic, Google, and Hyperbolic" do
      ["Novita", "Anthropic", "Google", "Hyperbolic"].each do |provider_name|
        allow(openai_double).to receive(:chat).and_return(
          chat_response(content: valid_payload_json, provider: provider_name)
        )

        adapter = described_class.new
        result = adapter.generate_bill_summary(prompt: prompt, model: model, schema: schema)
        expect(result).to be_present
        expect(adapter.last_upstream_company).to eq(provider_name)
      end
    end

    it "clears previous call attribution when a later call fails verification" do
      unattributed_response = {
        "choices" => [
          {"message" => {"content" => valid_payload_json}, "finish_reason" => "stop"}
        ]
      }
      allow(openai_double).to receive(:chat).and_return(
        chat_response(content: valid_payload_json, provider: "Together"),
        unattributed_response
      )
      adapter = described_class.new
      adapter.generate_bill_summary(prompt: prompt, model: model, schema: schema)
      expect(adapter.last_upstream_company).to eq("Together")

      expect {
        adapter.generate_bill_summary(prompt: prompt, model: model, schema: schema)
      }.to raise_error(Llm::OpenRouterAdapter::UnpinnedUpstreamError)
      expect(adapter.last_upstream_company).to be_nil
      expect(adapter.last_response).to be_nil
      expect(adapter.last_usage).to be_nil
    end

    it "refuses and raises UnpinnedUpstreamError when serving company attribution is absent" do
      unattributed_response = {
        "choices" => [
          {"message" => {"content" => valid_payload_json}, "finish_reason" => "stop"}
        ]
      }
      allow(openai_double).to receive(:chat).and_return(unattributed_response)

      expect {
        described_class.new.generate_bill_summary(prompt: prompt, model: model, schema: schema)
      }.to raise_error(Llm::OpenRouterAdapter::UnpinnedUpstreamError, /omitted serving upstream company attribution/)
    end

    it "rejects conflicting explicit serving company claims" do
      response = chat_response(content: valid_payload_json, provider: "Together")
      response["openrouter_metadata"]["endpoints"]["available"].first["provider"] = "DeepSeek"
      allow(openai_double).to receive(:chat).and_return(response)

      expect {
        described_class.new.generate_bill_summary(prompt: prompt, model: model, schema: schema)
      }.to raise_error(Llm::OpenRouterAdapter::UnpinnedUpstreamError, /conflicting serving upstream company attribution/)
    end

    it "treats differently cased claims for the same company as one attribution" do
      response = chat_response(content: valid_payload_json, provider: "together")
      response["openrouter_metadata"]["endpoints"]["available"].first["provider"] = "Together"
      allow(openai_double).to receive(:chat).and_return(response)

      result = described_class.new.generate_bill_summary(prompt: prompt, model: model, schema: schema)

      expect(result).to be_a(Hash)
    end

    it "requires an explicitly selected endpoint" do
      response = chat_response(content: valid_payload_json, provider: "Together")
      response["openrouter_metadata"]["endpoints"]["available"].first["selected"] = false
      allow(openai_double).to receive(:chat).and_return(response)

      expect {
        described_class.new.generate_bill_summary(prompt: prompt, model: model, schema: schema)
      }.to raise_error(Llm::OpenRouterAdapter::UnpinnedUpstreamError, /omitted serving upstream company attribution/)
    end

    it "rejects multiple selected endpoints even when both are in the allowed set" do
      response = chat_response(content: valid_payload_json, provider: "Together")
      response["openrouter_metadata"]["endpoints"]["available"] << {
        "provider" => "Fireworks",
        "selected" => true
      }
      allow(openai_double).to receive(:chat).and_return(response)

      expect {
        described_class.new.generate_bill_summary(prompt: prompt, model: model, schema: schema)
      }.to raise_error(Llm::OpenRouterAdapter::UnpinnedUpstreamError, /omitted serving upstream company attribution/)
    end

    it "normalizes malformed endpoint metadata instead of raising a Ruby type error" do
      response = chat_response(content: valid_payload_json, provider: "Together")
      response["openrouter_metadata"]["endpoints"] = []
      allow(openai_double).to receive(:chat).and_return(response)

      expect {
        described_class.new.generate_bill_summary(prompt: prompt, model: model, schema: schema)
      }.to raise_error(Llm::OpenRouterAdapter::UnpinnedUpstreamError, /omitted serving upstream company attribution/)
    end

    it "refuses and raises UnpinnedUpstreamError when provider metadata is a non-string object" do
      malformed_response = {
        "choices" => [
          {"message" => {"content" => valid_payload_json}, "finish_reason" => "stop"}
        ],
        "openrouter_metadata" => {
          "endpoints" => {
            "available" => [
              {"provider" => {"name" => "DeepSeek"}, "selected" => true}
            ]
          }
        }
      }
      allow(openai_double).to receive(:chat).and_return(malformed_response)

      expect {
        described_class.new.generate_bill_summary(prompt: prompt, model: model, schema: schema)
      }.to raise_error(Llm::OpenRouterAdapter::UnpinnedUpstreamError, /omitted serving upstream company attribution/)
    end

    it "refuses and raises UnpinnedUpstreamError when top-level or metadata provider is a non-string number" do
      malformed_response = {
        "choices" => [
          {"message" => {"content" => valid_payload_json}, "finish_reason" => "stop"}
        ],
        "provider" => 123,
        "openrouter_metadata" => {
          "provider" => 456
        }
      }
      allow(openai_double).to receive(:chat).and_return(malformed_response)

      expect {
        described_class.new.generate_bill_summary(prompt: prompt, model: model, schema: schema)
      }.to raise_error(Llm::OpenRouterAdapter::UnpinnedUpstreamError, /omitted serving upstream company attribution/)
    end

    it "refuses and raises UnpinnedUpstreamError when endpoints array contains non-hash elements" do
      malformed_response = {
        "choices" => [
          {"message" => {"content" => valid_payload_json}, "finish_reason" => "stop"}
        ],
        "openrouter_metadata" => {
          "endpoints" => {
            "available" => [nil, 123, "endpoint"]
          }
        }
      }
      allow(openai_double).to receive(:chat).and_return(malformed_response)

      expect {
        described_class.new.generate_bill_summary(prompt: prompt, model: model, schema: schema)
      }.to raise_error(Llm::OpenRouterAdapter::UnpinnedUpstreamError, /omitted serving upstream company attribution/)
    end

    it "refuses and raises UnpinnedUpstreamError when attempts array contains non-hash elements" do
      malformed_response = {
        "choices" => [
          {"message" => {"content" => valid_payload_json}, "finish_reason" => "stop"}
        ],
        "openrouter_metadata" => {
          "attempts" => [123]
        }
      }
      allow(openai_double).to receive(:chat).and_return(malformed_response)

      expect {
        described_class.new.generate_bill_summary(prompt: prompt, model: model, schema: schema)
      }.to raise_error(Llm::OpenRouterAdapter::UnpinnedUpstreamError, /omitted serving upstream company attribution/)
    end

    it "verifies served upstream when Auto resolves to a concrete model" do
      allow(openai_double).to receive(:chat).and_return(
        chat_response(
          content: valid_payload_json,
          provider: "Fireworks",
          model_name: "deepseek/deepseek-v4-flash-0731"
        )
      )

      expect(SwayLogging).to receive(:info).with(
        "openrouter.call.completed",
        hash_including(
          upstream_company: "Fireworks",
          model: "deepseek/deepseek-v4-flash-0731",
          requested_model: "openrouter/auto"
        )
      )

      adapter = described_class.new
      result = adapter.generate_bill_summary(prompt: prompt, model: "openrouter/auto", schema: schema)
      expect(result).to be_a(Hash)
      expect(adapter.last_upstream_company).to eq("Fireworks")
    end
  end

  describe "failure-handling policy and error classification" do
    it "classifies Faraday::TimeoutError as routing service failure" do
      allow(openai_double).to receive(:chat).and_raise(Faraday::TimeoutError.new("execution expired"))

      expect {
        described_class.new.generate_bill_summary(prompt: prompt, model: model, schema: schema)
      }.to raise_error(Llm::TransportError, /openrouter transport: routing service: Faraday::TimeoutError/)
    end

    it "normalizes a malformed successful response envelope into a transport error" do
      allow(openai_double).to receive(:chat).and_return([])

      expect {
        described_class.new.generate_bill_summary(prompt: prompt, model: model, schema: schema)
      }.to raise_error(Llm::TransportError, /malformed response envelope/)
    end

    it "classifies connection failure as routing service failure" do
      allow(openai_double).to receive(:chat).and_raise(Faraday::ConnectionFailed.new("connection refused"))

      expect {
        described_class.new.generate_bill_summary(prompt: prompt, model: model, schema: schema)
      }.to raise_error(Llm::TransportError, /openrouter transport: routing service: Faraday::ConnectionFailed/)
    end

    it "classifies HTTP 502/503 as model failure" do
      error = Faraday::ServerError.new(
        "bad gateway",
        {status: 502, body: {"error" => {"message" => "upstream model provider overloaded", "code" => 502}}}
      )
      allow(openai_double).to receive(:chat).and_raise(error)

      expect {
        described_class.new.generate_bill_summary(prompt: prompt, model: model, schema: schema)
      }.to raise_error(Llm::TransportError, /openrouter transport: model: Faraday::ServerError/)
    end

    it "normalizes HTTP errors with malformed provider metadata" do
      stub_request(:post, "https://openrouter.ai/api/v1/chat/completions").to_return(
        status: 400,
        headers: {"Content-Type" => "application/json"},
        body: {"error" => {"message" => "invalid request", "metadata" => []}}.to_json
      )
      allow(OpenAI::Client).to receive(:new).and_call_original

      expect {
        described_class.new.generate_bill_summary(prompt: prompt, model: model, schema: schema)
      }.to raise_error(Llm::TransportError, /openrouter transport: routing service: Faraday::BadRequest/)
    end

    it "configures retry middleware with OPENROUTER_DEFAULTS and extra headers" do
      conn = instance_double(Faraday::Connection)
      expect(conn).to receive(:request).with(:retry, Sway::FaradayStack::OPENROUTER_DEFAULTS)
      allow(OpenAI::Client).to receive(:new) do |**kwargs, &block|
        block&.call(conn)
        openai_double
      end

      described_class.new.send(:client)
      expect(OpenAI::Client).to have_received(:new).with(
        hash_including(
          uri_base: "https://openrouter.ai/api/v1",
          access_token: "sk-or-v1-test-key",
          request_timeout: 120,
          extra_headers: {"X-OpenRouter-Metadata" => "enabled"}
        )
      )
    end

    it "asserts OPENROUTER_DEFAULTS retries 429 but does not retry 5xx" do
      expect(Sway::FaradayStack::OPENROUTER_DEFAULTS[:retry_statuses]).to eq([429])
      expect(Sway::FaradayStack::OPENROUTER_DEFAULTS[:retry_statuses]).not_to include(500, 502, 503)
      expect(Sway::FaradayStack::OPENROUTER_DEFAULTS[:methods]).to eq([:post])
    end

    it "preserves the model and pinned policy in the real HTTP retry after a 429" do
      requests = []
      response_body = chat_response(content: valid_payload_json, provider: "Together").to_json
      stub_request(:post, "https://openrouter.ai/api/v1/chat/completions").to_return do |request|
        requests << JSON.parse(request.body)
        if requests.length == 1
          {status: 429, headers: {"Content-Type" => "application/json"}, body: {"error" => {"message" => "rate limited"}}.to_json}
        else
          {status: 200, headers: {"Content-Type" => "application/json"}, body: response_body}
        end
      end
      allow(OpenAI::Client).to receive(:new).and_call_original

      described_class.new.generate_bill_summary(prompt: prompt, model: model, schema: schema)

      expect(requests.length).to eq(2)
      expect(requests.first).to eq(requests.second)
      expect(requests.map { |body| body.fetch("model") }).to eq([model, model])
      expect(requests.map { |body| body.fetch("provider") }).to eq([
        {
          "data_collection" => "deny",
          "require_parameters" => true
        }
      ] * 2)
    end
  end

  describe "#generate_bill_categories" do
    let(:categories_schema) { BILL_CATEGORIES_SCHEMA_HASH }
    let(:valid_categories_json) { {"categories" => ["Health", "Environment"]}.to_json }

    it "returns the parsed categories hash" do
      allow(openai_double).to receive(:chat).and_return(chat_response(content: valid_categories_json))
      result = described_class.new.generate_bill_categories(
        prompt: prompt, model: model, schema: categories_schema
      )
      expect(result).to eq({"categories" => ["Health", "Environment"]})
    end
  end

  describe "#generate_bill_positions" do
    let(:positions_schema) { BILL_POSITIONS_SCHEMA_HASH }
    let(:valid_positions_json) do
      {
        "draft_org_positions" => [
          {"org_name" => "ACLU", "stance" => "support", "summary" => "Civil liberties defense."}
        ]
      }.to_json
    end

    it "returns the parsed positions hash" do
      allow(openai_double).to receive(:chat).and_return(chat_response(content: valid_positions_json))
      result = described_class.new.generate_bill_positions(
        prompt: prompt, model: model, schema: positions_schema
      )
      expect(result["draft_org_positions"].first["org_name"]).to eq("ACLU")
    end
  end

  describe "#generate_testimony_classification" do
    let(:classification_schema) { TESTIMONY_CLASSIFICATION_SCHEMA_HASH }
    let(:valid_classification_json) do
      {
        "classifications" => [
          {"index" => 0, "label" => "testimony"}
        ]
      }.to_json
    end

    it "returns the parsed classification hash" do
      allow(openai_double).to receive(:chat).and_return(chat_response(content: valid_classification_json))
      result = described_class.new.generate_testimony_classification(
        prompt: prompt, model: model, schema: classification_schema
      )
      expect(result["classifications"].first["label"]).to eq("testimony")
    end
  end

  describe "#generate_source_kind_classification" do
    it "returns the parsed source kind classification hash" do
      source_kind_schema = SOURCE_KIND_CLASSIFICATION_SCHEMA_HASH
      valid_source_kind_json = {
        "classifications" => [
          {"position" => 0, "kind" => "named_organization"}
        ]
      }.to_json

      allow(openai_double).to receive(:chat).and_return(chat_response(content: valid_source_kind_json))
      result = described_class.new.generate_source_kind_classification(
        prompt: prompt, model: model, schema: source_kind_schema
      )
      expect(result["classifications"].first["kind"]).to eq("named_organization")
    end
  end

  describe "#generate_testimony_stance_classification" do
    it "returns the parsed testimony stance classification hash" do
      stance_schema = TESTIMONY_STANCE_CLASSIFICATION_SCHEMA_HASH
      valid_stance_json = {
        "classifications" => [
          {"position" => 0, "stance" => "support"}
        ]
      }.to_json

      allow(openai_double).to receive(:chat).and_return(chat_response(content: valid_stance_json))
      result = described_class.new.generate_testimony_stance_classification(
        prompt: prompt, model: model, schema: stance_schema
      )
      expect(result["classifications"].first["stance"]).to eq("support")
    end

    it "raises Llm::SchemaError for invalid schema payload" do
      stance_schema = TESTIMONY_STANCE_CLASSIFICATION_SCHEMA_HASH
      allow(openai_double).to receive(:chat).and_return(chat_response(content: {"invalid" => "payload"}.to_json))
      expect {
        described_class.new.generate_testimony_stance_classification(
          prompt: prompt, model: model, schema: stance_schema
        )
      }.to raise_error(Llm::SchemaError)
    end
  end

  describe "#generate_news_claim_grounding" do
    it "returns the parsed grounding hash" do
      grounding_schema = NEWS_CLAIM_GROUNDING_SCHEMA_HASH
      valid_grounding_json = {
        "verdict" => "supported",
        "reason" => "Grounding corroborated."
      }.to_json

      allow(openai_double).to receive(:chat).and_return(chat_response(content: valid_grounding_json))
      result = described_class.new.generate_news_claim_grounding(
        prompt: prompt, model: model, schema: grounding_schema
      )
      expect(result).to eq({"verdict" => "supported", "reason" => "Grounding corroborated."})
    end
  end

  describe "reasoning_effort parameter support" do
    let(:adapter) { described_class.new }

    it "omits reasoning key and keeps max_tokens: 4096 when reasoning_effort is nil or blank" do
      expect(openai_double).to receive(:chat) do |args|
        params = args.fetch(:parameters)
        expect(params).not_to have_key(:reasoning)
        expect(params[:max_tokens]).to eq(4096)
        chat_response(content: valid_payload_json)
      end

      adapter.generate_bill_summary(prompt: prompt, model: model, schema: schema, reasoning_effort: nil)
    end

    %w[low medium high].each do |level|
      it "sends reasoning: { effort: '#{level}' } and sets max_tokens: 16_384 when reasoning_effort is '#{level}'" do
        expect(openai_double).to receive(:chat) do |args|
          params = args.fetch(:parameters)
          expect(params[:reasoning]).to eq({effort: level})
          expect(params[:max_tokens]).to eq(16_384)
          chat_response(content: valid_payload_json)
        end

        adapter.generate_bill_summary(prompt: prompt, model: model, schema: schema, reasoning_effort: level)
      end
    end

    it "raises ArgumentError when reasoning_effort is unsupported before making an HTTP request" do
      expect(openai_double).not_to receive(:chat)

      expect {
        adapter.generate_bill_summary(prompt: prompt, model: model, schema: schema, reasoning_effort: "ultra")
      }.to raise_error(ArgumentError, /unsupported reasoning_effort: "ultra"/)
    end
  end

  describe "#generate_decisions" do
    before do
      @adapter = described_class.new
      @decisions_model = "scaledown/classify-1"
      @state = {
        "attachment" => {
          "title" => "Letter of Support",
          "text" => "We write in strong support of Bill 24-001."
        }
      }
      @questions = {
        "is_testimony" => {
          "type" => "choice",
          "instructions" => "Is this attachment public testimony?",
          "criteria" => {
            "testimony" => "Written or oral testimony",
            "not_testimony" => "Bill text or fiscal note"
          }
        },
        "testimony_prob" => {
          "type" => "noul",
          "instructions" => "Probability that this is testimony"
        },
        "relevance_score" => {
          "type" => "score",
          "instructions" => "Relevance score from 1 to 5"
        }
      }
      @valid_decisions_answers = {
        "is_testimony" => {
          "type" => "choice",
          "choice" => "testimony",
          "probabilities" => {"testimony" => 0.94, "not_testimony" => 0.06}
        },
        "testimony_prob" => {
          "type" => "noul",
          "noul" => 0.94
        },
        "relevance_score" => {
          "type" => "score",
          "score" => 5
        }
      }
      @decisions_response_body = {
        "model" => @decisions_model,
        "provider" => "ScaleDown",
        "usage" => {
          "prompt_tokens" => 80,
          "completion_tokens" => 25,
          "total_tokens" => 105
        },
        "answers" => @valid_decisions_answers
      }
    end

    it "posts payload to /api/alpha/decisions with Bearer auth and X-OpenRouter-Metadata header" do
      stub = stub_request(:post, "https://openrouter.ai/api/alpha/decisions")
        .with(
          headers: {
            "Authorization" => "Bearer sk-or-v1-test-key",
            "Content-Type" => "application/json",
            "X-OpenRouter-Metadata" => "enabled"
          },
          body: {
            model: @decisions_model,
            state: @state,
            questions: @questions,
            provider: {data_collection: "deny"}
          }.to_json
        )
        .to_return(
          status: 200,
          headers: {"Content-Type" => "application/json"},
          body: @decisions_response_body.to_json
        )

      result = @adapter.generate_decisions(model: @decisions_model, state: @state, questions: @questions)
      expect(stub).to have_been_requested
      expect(result["answers"]["is_testimony"]["choice"]).to eq("testimony")
      expect(@adapter.last_upstream_company).to eq("ScaleDown")
      expect(@adapter.last_usage["total_tokens"]).to eq(105)
      expect(@adapter.last_response).to be_present
    end

    it "processes valid noul answers across boundary values 0.0, 0.5, 1.0, and integer 0/1" do
      [0.0, 0.5, 1.0, 0, 1].each do |prob|
        noul_answers = @valid_decisions_answers.merge(
          "testimony_prob" => {"type" => "noul", "noul" => prob}
        )
        stub_request(:post, "https://openrouter.ai/api/alpha/decisions").to_return(
          status: 200,
          headers: {"Content-Type" => "application/json"},
          body: @decisions_response_body.merge("answers" => noul_answers).to_json
        )

        res = @adapter.generate_decisions(model: @decisions_model, state: @state, questions: @questions)
        expect(res["answers"]["testimony_prob"]["noul"]).to eq(prob)
      end
    end

    it "processes valid score answers as Integer, Float, negative Numeric, and non-empty String" do
      [5, 4.25, -1, 0, "A+", "very_high", "10/10"].each do |val|
        score_answers = @valid_decisions_answers.merge(
          "relevance_score" => {"type" => "score", "score" => val}
        )
        stub_request(:post, "https://openrouter.ai/api/alpha/decisions").to_return(
          status: 200,
          headers: {"Content-Type" => "application/json"},
          body: @decisions_response_body.merge("answers" => score_answers).to_json
        )

        res = @adapter.generate_decisions(model: @decisions_model, state: @state, questions: @questions)
        expect(res["answers"]["relevance_score"]["score"]).to eq(val)
      end
    end

    it "tolerates symbol-keyed questions input and stringifies them cleanly in validation" do
      symbol_questions = {
        is_testimony: {
          type: :choice,
          instructions: "Classify"
        }
      }
      symbol_answers = {
        "is_testimony" => {
          "type" => "choice",
          "choice" => "testimony",
          "probabilities" => {"testimony" => 1.0}
        }
      }
      stub_request(:post, "https://openrouter.ai/api/alpha/decisions").to_return(
        status: 200,
        headers: {"Content-Type" => "application/json"},
        body: @decisions_response_body.merge("answers" => symbol_answers).to_json
      )

      res = @adapter.generate_decisions(model: @decisions_model, state: @state, questions: symbol_questions)
      expect(res["answers"]["is_testimony"]["choice"]).to eq("testimony")
    end

    it "allows additional answer keys returned by upstream without failing validation" do
      extra_answers = @valid_decisions_answers.merge(
        "unrequested_metric" => {
          "type" => "score",
          "score" => 100
        }
      )
      stub_request(:post, "https://openrouter.ai/api/alpha/decisions").to_return(
        status: 200,
        headers: {"Content-Type" => "application/json"},
        body: @decisions_response_body.merge("answers" => extra_answers).to_json
      )

      res = @adapter.generate_decisions(model: @decisions_model, state: @state, questions: @questions)
      expect(res["answers"]).to have_key("unrequested_metric")
    end

    it "coerces nil, array, or scalar state to empty Hash payload without raising" do
      stub = stub_request(:post, "https://openrouter.ai/api/alpha/decisions")
        .with { |req| JSON.parse(req.body)["state"] == {} }
        .to_return(
          status: 200,
          headers: {"Content-Type" => "application/json"},
          body: @decisions_response_body.to_json
        )

      [nil, "scalar_state", [1, 2]].each do |non_hash_state|
        res = @adapter.generate_decisions(model: @decisions_model, state: non_hash_state, questions: @questions)
        expect(res["answers"]["is_testimony"]["choice"]).to eq("testimony")
      end

      expect(stub).to have_been_requested.times(3)
    end

    it "derives custom decisions endpoint when openrouter_base_url is customized" do
      with_app_config(:llm, openrouter_base_url: "https://custom.openrouter.test/api/v1") do
        stub = stub_request(:post, "https://custom.openrouter.test/api/alpha/decisions")
          .to_return(
            status: 200,
            headers: {"Content-Type" => "application/json"},
            body: @decisions_response_body.to_json
          )

        @adapter.generate_decisions(model: @decisions_model, state: @state, questions: @questions)
        expect(stub).to have_been_requested
      end
    end

    it "derives custom decisions endpoint when openrouter_base_url does not end in /v1" do
      with_app_config(:llm, openrouter_base_url: "https://proxy.example.com/api") do
        stub = stub_request(:post, "https://proxy.example.com/api/alpha/decisions")
          .to_return(
            status: 200,
            headers: {"Content-Type" => "application/json"},
            body: @decisions_response_body.to_json
          )

        @adapter.generate_decisions(model: @decisions_model, state: @state, questions: @questions)
        expect(stub).to have_been_requested
      end
    end

    it "preserves custom decisions endpoint when openrouter_base_url already ends in /alpha/decisions" do
      with_app_config(:llm, openrouter_base_url: "https://proxy.example.com/api/alpha/decisions/") do
        stub = stub_request(:post, "https://proxy.example.com/api/alpha/decisions")
          .to_return(
            status: 200,
            headers: {"Content-Type" => "application/json"},
            body: @decisions_response_body.to_json
          )

        @adapter.generate_decisions(model: @decisions_model, state: @state, questions: @questions)
        expect(stub).to have_been_requested
      end
    end

    it "accepts attribution provided via openrouter_metadata when present" do
      body_with_metadata = @decisions_response_body.merge(
        "openrouter_metadata" => {
          "endpoints" => {
            "available" => [
              {"provider" => "ScaleDown", "selected" => true}
            ]
          }
        }
      )
      stub_request(:post, "https://openrouter.ai/api/alpha/decisions")
        .to_return(
          status: 200,
          headers: {"Content-Type" => "application/json"},
          body: body_with_metadata.to_json
        )

      @adapter.generate_decisions(model: @decisions_model, state: @state, questions: @questions)
      expect(@adapter.last_upstream_company).to eq("ScaleDown")
    end

    it "verifies attribution from openrouter_metadata with available_endpoints list" do
      metadata_body = @decisions_response_body.except("provider").merge(
        "openrouter_metadata" => {
          "available_endpoints" => [
            {"provider" => "ScaleDown", "selected" => true}
          ]
        }
      )
      stub_request(:post, "https://openrouter.ai/api/alpha/decisions")
        .to_return(
          status: 200,
          headers: {"Content-Type" => "application/json"},
          body: metadata_body.to_json
        )

      @adapter.generate_decisions(model: @decisions_model, state: @state, questions: @questions)
      expect(@adapter.last_upstream_company).to eq("ScaleDown")
    end

    it "falls back to top-level provider_name when provider and metadata are absent" do
      body = @decisions_response_body.except("provider").merge("provider_name" => "ScaleDown")
      stub_request(:post, "https://openrouter.ai/api/alpha/decisions")
        .to_return(
          status: 200,
          headers: {"Content-Type" => "application/json"},
          body: body.to_json
        )

      @adapter.generate_decisions(model: @decisions_model, state: @state, questions: @questions)
      expect(@adapter.last_upstream_company).to eq("ScaleDown")
    end

    it "accepts agreeing provider and provider_name with different casing" do
      body = @decisions_response_body.merge("provider" => "ScaleDown", "provider_name" => "scaledown")
      stub_request(:post, "https://openrouter.ai/api/alpha/decisions")
        .to_return(
          status: 200,
          headers: {"Content-Type" => "application/json"},
          body: body.to_json
        )

      @adapter.generate_decisions(model: @decisions_model, state: @state, questions: @questions)
      expect(@adapter.last_upstream_company).to eq("ScaleDown")
    end

    it "raises UnpinnedUpstreamError when serving provider attribution is absent" do
      body_without_provider = @decisions_response_body.except("provider")
      stub_request(:post, "https://openrouter.ai/api/alpha/decisions")
        .to_return(
          status: 200,
          headers: {"Content-Type" => "application/json"},
          body: body_without_provider.to_json
        )

      expect {
        @adapter.generate_decisions(model: @decisions_model, state: @state, questions: @questions)
      }.to raise_error(Llm::OpenRouterAdapter::UnpinnedUpstreamError, /omitted serving upstream company attribution/)
    end

    it "raises UnpinnedUpstreamError when top-level provider and provider_name conflict" do
      conflicting_body = @decisions_response_body.merge(
        "provider" => "ScaleDown",
        "provider_name" => "Together"
      )
      stub_request(:post, "https://openrouter.ai/api/alpha/decisions")
        .to_return(
          status: 200,
          headers: {"Content-Type" => "application/json"},
          body: conflicting_body.to_json
        )

      expect {
        @adapter.generate_decisions(model: @decisions_model, state: @state, questions: @questions)
      }.to raise_error(Llm::OpenRouterAdapter::UnpinnedUpstreamError, /conflicting serving upstream company attribution/)
    end

    it "raises UnpinnedUpstreamError when metadata provider conflicts with top-level provider" do
      conflicting_metadata = @decisions_response_body.merge(
        "provider" => "ScaleDown",
        "openrouter_metadata" => {
          "endpoints" => {
            "available" => [
              {"provider" => "Together", "selected" => true}
            ]
          }
        }
      )
      stub_request(:post, "https://openrouter.ai/api/alpha/decisions")
        .to_return(
          status: 200,
          headers: {"Content-Type" => "application/json"},
          body: conflicting_metadata.to_json
        )

      expect {
        @adapter.generate_decisions(model: @decisions_model, state: @state, questions: @questions)
      }.to raise_error(Llm::OpenRouterAdapter::UnpinnedUpstreamError, /conflicting serving upstream company attribution/)
    end

    it "raises UnpinnedUpstreamError when metadata has zero or multiple selected endpoints and no fallback" do
      no_selected_body = @decisions_response_body.except("provider").merge(
        "openrouter_metadata" => {
          "endpoints" => {
            "available" => [
              {"provider" => "ScaleDown", "selected" => false}
            ]
          }
        }
      )
      stub_request(:post, "https://openrouter.ai/api/alpha/decisions")
        .to_return(
          status: 200,
          headers: {"Content-Type" => "application/json"},
          body: no_selected_body.to_json
        )

      expect {
        @adapter.generate_decisions(model: @decisions_model, state: @state, questions: @questions)
      }.to raise_error(Llm::OpenRouterAdapter::UnpinnedUpstreamError, /omitted serving upstream company attribution/)

      multi_selected_body = @decisions_response_body.except("provider").merge(
        "openrouter_metadata" => {
          "endpoints" => {
            "available" => [
              {"provider" => "ScaleDown", "selected" => true},
              {"provider" => "Together", "selected" => true}
            ]
          }
        }
      )
      stub_request(:post, "https://openrouter.ai/api/alpha/decisions")
        .to_return(
          status: 200,
          headers: {"Content-Type" => "application/json"},
          body: multi_selected_body.to_json
        )

      expect {
        @adapter.generate_decisions(model: @decisions_model, state: @state, questions: @questions)
      }.to raise_error(Llm::OpenRouterAdapter::UnpinnedUpstreamError, /omitted serving upstream company attribution/)
    end

    it "raises ArgumentError when model is blank or questions is empty" do
      expect {
        @adapter.generate_decisions(model: "", state: @state, questions: @questions)
      }.to raise_error(ArgumentError, /model must be specified/)

      expect {
        @adapter.generate_decisions(model: @decisions_model, state: @state, questions: {})
      }.to raise_error(ArgumentError, /questions must be a non-empty Hash/)
    end

    it "raises ArgumentError when questions is an Array or scalar" do
      [[], [{"type" => "choice"}], "questions", 42, true].each do |bad_q|
        expect {
          @adapter.generate_decisions(model: @decisions_model, state: @state, questions: bad_q)
        }.to raise_error(ArgumentError, /questions must be a non-empty Hash/)
      end
    end

    it "raises Llm::SchemaError when answers key is missing or empty" do
      stub_request(:post, "https://openrouter.ai/api/alpha/decisions")
        .to_return(
          status: 200,
          headers: {"Content-Type" => "application/json"},
          body: {"model" => @decisions_model, "provider" => "ScaleDown"}.to_json
        )

      expect {
        @adapter.generate_decisions(model: @decisions_model, state: @state, questions: @questions)
      }.to raise_error(Llm::SchemaError, /answers must be a non-empty Hash/)
    end

    it "raises Llm::SchemaError when an answer key is omitted" do
      truncated_answers = @valid_decisions_answers.except("relevance_score")
      stub_request(:post, "https://openrouter.ai/api/alpha/decisions")
        .to_return(
          status: 200,
          headers: {"Content-Type" => "application/json"},
          body: @decisions_response_body.merge("answers" => truncated_answers).to_json
        )

      expect {
        @adapter.generate_decisions(model: @decisions_model, state: @state, questions: @questions)
      }.to raise_error(Llm::SchemaError, /missing answers for questions: relevance_score/)
    end

    it "raises Llm::SchemaError when an individual answer is not a Hash" do
      ["support", 42, true, nil, [1, 2]].each do |bad_val|
        bad_answers = @valid_decisions_answers.merge("is_testimony" => bad_val)
        stub_request(:post, "https://openrouter.ai/api/alpha/decisions").to_return(
          status: 200,
          headers: {"Content-Type" => "application/json"},
          body: @decisions_response_body.merge("answers" => bad_answers).to_json
        )

        expect {
          @adapter.generate_decisions(model: @decisions_model, state: @state, questions: @questions)
        }.to raise_error(Llm::SchemaError, /answer for is_testimony must be a Hash/)
      end
    end

    it "raises Llm::SchemaError when answer type conflicts with question type" do
      mismatched_answers = @valid_decisions_answers.merge(
        "is_testimony" => {
          "type" => "noul",
          "noul" => 0.8
        }
      )
      stub_request(:post, "https://openrouter.ai/api/alpha/decisions").to_return(
        status: 200,
        headers: {"Content-Type" => "application/json"},
        body: @decisions_response_body.merge("answers" => mismatched_answers).to_json
      )

      expect {
        @adapter.generate_decisions(model: @decisions_model, state: @state, questions: @questions)
      }.to raise_error(Llm::SchemaError, /question is_testimony expects type choice, got noul/)
    end

    it "raises Llm::SchemaError on unrecognized answer types" do
      questions = {"untyped_q" => {"instructions" => "No explicit type defined"}}
      ["free_text", "untyped", "", "json", 123].each do |bad_type|
        bad_answers = {
          "untyped_q" => {
            "type" => bad_type,
            "score" => 5
          }
        }
        stub_request(:post, "https://openrouter.ai/api/alpha/decisions").to_return(
          status: 200,
          headers: {"Content-Type" => "application/json"},
          body: @decisions_response_body.merge("answers" => bad_answers).to_json
        )

        expect {
          @adapter.generate_decisions(model: @decisions_model, state: @state, questions: questions)
        }.to raise_error(Llm::SchemaError, /unrecognized answer type/)
      end
    end

    it "raises Llm::SchemaError when choice answer is missing choice or probabilities" do
      bad_answers = @valid_decisions_answers.merge(
        "is_testimony" => {"type" => "choice", "choice" => ""}
      )
      stub_request(:post, "https://openrouter.ai/api/alpha/decisions")
        .to_return(
          status: 200,
          headers: {"Content-Type" => "application/json"},
          body: @decisions_response_body.merge("answers" => bad_answers).to_json
        )

      expect {
        @adapter.generate_decisions(model: @decisions_model, state: @state, questions: @questions)
      }.to raise_error(Llm::SchemaError, /choice answer for is_testimony must have a non-blank String 'choice'/)
    end

    it "raises Llm::SchemaError when choice answer probabilities contain non-numeric, out-of-range, or non-finite values" do
      [
        {"testimony" => 1.5, "not_testimony" => -0.5},
        {"testimony" => -0.1, "not_testimony" => 1.1},
        {"testimony" => Float::NAN, "not_testimony" => 0.5},
        {"testimony" => Float::INFINITY, "not_testimony" => 0.0},
        {"testimony" => "high", "not_testimony" => "low"}
      ].each do |bad_probs|
        bad_answers = @valid_decisions_answers.merge(
          "is_testimony" => {"type" => "choice", "choice" => "testimony", "probabilities" => bad_probs}
        )
        stub_request(:post, "https://openrouter.ai/api/alpha/decisions")
          .to_return(
            status: 200,
            headers: {"Content-Type" => "application/json"},
            body: @decisions_response_body.merge("answers" => bad_answers).to_json
          )

        expect {
          @adapter.generate_decisions(model: @decisions_model, state: @state, questions: @questions)
        }.to raise_error(Llm::SchemaError, /choice answer for is_testimony must have numeric probabilities between 0.0 and 1.0/)
      end
    end

    it "raises Llm::SchemaError when choice answer confidence is invalid or non-finite" do
      [1.5, -0.1, "high", true, false, [1.0]].each do |bad_conf|
        bad_answers = @valid_decisions_answers.merge(
          "is_testimony" => {
            "type" => "choice",
            "choice" => "testimony",
            "probabilities" => {"testimony" => 0.95, "not_testimony" => 0.05},
            "confidence" => bad_conf
          }
        )
        stub_request(:post, "https://openrouter.ai/api/alpha/decisions")
          .to_return(
            status: 200,
            headers: {"Content-Type" => "application/json"},
            body: @decisions_response_body.merge("answers" => bad_answers).to_json
          )

        expect {
          @adapter.generate_decisions(model: @decisions_model, state: @state, questions: @questions)
        }.to raise_error(Llm::SchemaError, /choice answer for is_testimony must have a Numeric 'confidence' between 0.0 and 1.0/)
      end

      [Float::NAN, Float::INFINITY].each do |non_finite|
        bad = @valid_decisions_answers.merge(
          "is_testimony" => {
            "type" => "choice",
            "choice" => "testimony",
            "probabilities" => {"testimony" => 1.0},
            "confidence" => non_finite
          }
        )
        expect {
          @adapter.send(:validate_decisions_answers!, bad, @questions)
        }.to raise_error(Llm::SchemaError, /choice answer for is_testimony must have a Numeric 'confidence' between 0.0 and 1.0/)
      end

      bad_false_conf = @valid_decisions_answers.merge(
        "is_testimony" => {
          "type" => "choice",
          "choice" => "testimony",
          "probabilities" => {"testimony" => 1.0},
          "confidence" => false
        }
      )
      expect {
        @adapter.send(:validate_decisions_answers!, bad_false_conf, @questions)
      }.to raise_error(Llm::SchemaError, /choice answer for is_testimony must have a Numeric 'confidence' between 0.0 and 1.0/)
    end

    it "raises Llm::SchemaError when choice is not included in question criteria" do
      bad_answers = @valid_decisions_answers.merge(
        "is_testimony" => {
          "type" => "choice",
          "choice" => "neutral",
          "probabilities" => {"neutral" => 1.0}
        }
      )
      stub_request(:post, "https://openrouter.ai/api/alpha/decisions")
        .to_return(
          status: 200,
          headers: {"Content-Type" => "application/json"},
          body: @decisions_response_body.merge("answers" => bad_answers).to_json
        )

      expect {
        @adapter.generate_decisions(model: @decisions_model, state: @state, questions: @questions)
      }.to raise_error(Llm::SchemaError, /choice "neutral" for is_testimony is not in criteria choices/)
    end

    it "raises Llm::SchemaError when noul answer has non-numeric, out-of-bounds, or non-finite probability" do
      [1.5, -0.1, Float::NAN, Float::INFINITY, "not_a_number"].each do |bad_val|
        bad_answers = @valid_decisions_answers.merge(
          "testimony_prob" => {"type" => "noul", "noul" => bad_val}
        )
        stub_request(:post, "https://openrouter.ai/api/alpha/decisions")
          .to_return(
            status: 200,
            headers: {"Content-Type" => "application/json"},
            body: @decisions_response_body.merge("answers" => bad_answers).to_json
          )

        expect {
          @adapter.generate_decisions(model: @decisions_model, state: @state, questions: @questions)
        }.to raise_error(Llm::SchemaError, /probability between 0.0 and 1.0/)
      end
    end

    it "raises Llm::SchemaError when score answer is invalid, non-finite, or blank" do
      ["", "   ", Float::NAN, Float::INFINITY, nil, [1], {score: 5}].each do |bad_val|
        bad_answers = @valid_decisions_answers.merge(
          "relevance_score" => {"type" => "score", "score" => bad_val}
        )
        stub_request(:post, "https://openrouter.ai/api/alpha/decisions")
          .to_return(
            status: 200,
            headers: {"Content-Type" => "application/json"},
            body: @decisions_response_body.merge("answers" => bad_answers).to_json
          )

        expect {
          @adapter.generate_decisions(model: @decisions_model, state: @state, questions: @questions)
        }.to raise_error(Llm::SchemaError, /score answer for relevance_score must have a Numeric or String 'score'/)
      end
    end

    it "raises Llm::TransportError with classified failure side on HTTP 400" do
      stub_request(:post, "https://openrouter.ai/api/alpha/decisions")
        .to_return(
          status: 400,
          headers: {"Content-Type" => "application/json"},
          body: {"error" => {"message" => "bad request format", "code" => 400}}.to_json
        )

      expect {
        @adapter.generate_decisions(model: @decisions_model, state: @state, questions: @questions)
      }.to raise_error(Llm::TransportError, /openrouter transport: routing service: Faraday::BadRequest/)
    end

    it "raises Llm::TransportError with classified failure side on HTTP 502/503" do
      stub_request(:post, "https://openrouter.ai/api/alpha/decisions")
        .to_return(
          status: 502,
          headers: {"Content-Type" => "application/json"},
          body: {"error" => {"message" => "upstream model provider timeout", "code" => 502}}.to_json
        )

      expect {
        @adapter.generate_decisions(model: @decisions_model, state: @state, questions: @questions)
      }.to raise_error(Llm::TransportError, /openrouter transport: model: Faraday::ServerError/)
    end

    it "classifies HTTP 401, 403, and 429 as routing service failures" do
      [
        [401, Faraday::UnauthorizedError, "Invalid API key"],
        [403, Faraday::ForbiddenError, "Account restricted"],
        [429, Faraday::TooManyRequestsError, "Rate limit exceeded"]
      ].each do |status, err_class, msg|
        stub_request(:post, "https://openrouter.ai/api/alpha/decisions").to_return(
          status: status,
          headers: {"Content-Type" => "application/json"},
          body: {"error" => {"message" => msg, "code" => status}}.to_json
        )

        expect {
          @adapter.generate_decisions(model: @decisions_model, state: @state, questions: @questions)
        }.to raise_error(Llm::TransportError, /openrouter transport: routing service: #{err_class}/)
      end
    end

    it "classifies HTTP 500 without upstream keywords as routing service failure" do
      stub_request(:post, "https://openrouter.ai/api/alpha/decisions").to_return(
        status: 500,
        headers: {"Content-Type" => "application/json"},
        body: {"error" => {"message" => "Internal router error", "code" => 500}}.to_json
      )

      expect {
        @adapter.generate_decisions(model: @decisions_model, state: @state, questions: @questions)
      }.to raise_error(Llm::TransportError, /openrouter transport: routing service: Faraday::ServerError/)
    end

    it "classifies HTTP 500 mentioning upstream/model/provider as model failure" do
      stub_request(:post, "https://openrouter.ai/api/alpha/decisions").to_return(
        status: 500,
        headers: {"Content-Type" => "application/json"},
        body: {"error" => {"message" => "upstream provider returned 500", "code" => 500}}.to_json
      )

      expect {
        @adapter.generate_decisions(model: @decisions_model, state: @state, questions: @questions)
      }.to raise_error(Llm::TransportError, /openrouter transport: model: Faraday::ServerError/)
    end

    it "handles Faraday::TimeoutError and Faraday::ConnectionFailed cleanly" do
      stub_request(:post, "https://openrouter.ai/api/alpha/decisions").to_raise(Faraday::TimeoutError.new("request timed out"))

      expect {
        @adapter.generate_decisions(model: @decisions_model, state: @state, questions: @questions)
      }.to raise_error(Llm::TransportError, /openrouter transport: routing service: Faraday::TimeoutError/)

      stub_request(:post, "https://openrouter.ai/api/alpha/decisions").to_raise(Faraday::ConnectionFailed.new("connection refused"))

      expect {
        @adapter.generate_decisions(model: @decisions_model, state: @state, questions: @questions)
      }.to raise_error(Llm::TransportError, /openrouter transport: routing service: Faraday::ConnectionFailed/)
    end

    it "raises Llm::TransportError on empty response body" do
      stub_request(:post, "https://openrouter.ai/api/alpha/decisions")
        .to_return(
          status: 200,
          headers: {"Content-Type" => "application/json"},
          body: "   "
        )

      expect {
        @adapter.generate_decisions(model: @decisions_model, state: @state, questions: @questions)
      }.to raise_error(Llm::TransportError, /openrouter transport: empty response/)
    end

    it "raises Llm::SchemaError on malformed JSON body" do
      stub_request(:post, "https://openrouter.ai/api/alpha/decisions")
        .to_return(
          status: 200,
          headers: {"Content-Type" => "application/json"},
          body: "{not-valid-json}"
        )

      expect {
        @adapter.generate_decisions(model: @decisions_model, state: @state, questions: @questions)
      }.to raise_error(Llm::SchemaError, /failed to parse response JSON/)
    end

    it "raises Llm::TransportError on non-Hash JSON envelope" do
      stub_request(:post, "https://openrouter.ai/api/alpha/decisions")
        .to_return(
          status: 200,
          headers: {"Content-Type" => "application/json"},
          body: [1, 2, 3].to_json
        )

      expect {
        @adapter.generate_decisions(model: @decisions_model, state: @state, questions: @questions)
      }.to raise_error(Llm::TransportError, /malformed response envelope/)
    end
  end

  describe "#generate_entity_extraction" do
    before do
      @adapter = described_class.new
      @extract_model = "scaledown/extract"
      @content = "Jane Doe, Legislative Director at ACLU Maryland, testified in support."
      @entities = {
        spokesperson_name: "The full name of the authorized speaker or officer.",
        spokesperson_title: "The job title or organizational role of the speaker."
      }
      @extracted_json = {
        "spokesperson_name" => "Jane Doe",
        "spokesperson_title" => "Legislative Director"
      }.to_json
    end

    it "sends chat request with provider.options.scaledown.entities without response_format" do
      expect(openai_double).to receive(:chat) do |parameters:|
        params = parameters.dig(:parameters) || parameters
        expect(params[:model]).to eq(@extract_model)
        expect(params[:messages]).to eq([{role: "user", content: @content}])
        expect(params).not_to have_key(:response_format)
        expect(params[:max_tokens]).to eq(4096)
        expect(params.dig(:provider, :options, :scaledown, :entities)).to eq(
          "spokesperson_name" => "The full name of the authorized speaker or officer.",
          "spokesperson_title" => "The job title or organizational role of the speaker."
        )
        chat_response(content: @extracted_json, provider: "ScaleDown")
      end

      result = @adapter.generate_entity_extraction(
        model: @extract_model,
        content: @content,
        entities: @entities
      )
      expect(result).to eq(
        "spokesperson_name" => "Jane Doe",
        "spokesperson_title" => "Legislative Director"
      )
      expect(@adapter.last_upstream_company).to eq("ScaleDown")
    end

    it "honors custom max_tokens parameter when specified" do
      expect(openai_double).to receive(:chat) do |parameters:|
        params = parameters.dig(:parameters) || parameters
        expect(params[:max_tokens]).to eq(1024)
        chat_response(content: @extracted_json, provider: "ScaleDown")
      end

      @adapter.generate_entity_extraction(
        model: @extract_model,
        content: @content,
        entities: @entities,
        max_tokens: 1024
      )
    end

    it "raises ArgumentError when model is nil, empty string, or whitespace" do
      [nil, "", "   ", 123].each do |bad_model|
        expect {
          @adapter.generate_entity_extraction(model: bad_model, content: @content, entities: @entities)
        }.to raise_error(ArgumentError, "model must be a non-blank String")
      end
    end

    it "raises ArgumentError when content is nil, empty string, or whitespace" do
      [nil, "", "   ", 123].each do |bad_content|
        expect {
          @adapter.generate_entity_extraction(model: @extract_model, content: bad_content, entities: @entities)
        }.to raise_error(ArgumentError, "content must be a non-blank String")
      end
    end

    it "raises ArgumentError when entities is empty or not a Hash" do
      expect {
        @adapter.generate_entity_extraction(model: @extract_model, content: @content, entities: {})
      }.to raise_error(ArgumentError, /entities must be a non-empty Hash/)

      expect {
        @adapter.generate_entity_extraction(model: @extract_model, content: @content, entities: ["name"])
      }.to raise_error(ArgumentError, /entities must be a non-empty Hash/)
    end

    it "raises ArgumentError when an entity description is blank" do
      expect {
        @adapter.generate_entity_extraction(
          model: @extract_model,
          content: @content,
          entities: {spokesperson: "   "}
        )
      }.to raise_error(ArgumentError, /entity description for :spokesperson must be a non-blank String/)
    end

    it "raises Llm::SchemaError when finish_reason is length" do
      allow(openai_double).to receive(:chat).and_return(
        chat_response(content: @extracted_json, finish_reason: "length", provider: "ScaleDown")
      )

      expect {
        @adapter.generate_entity_extraction(model: @extract_model, content: @content, entities: @entities)
      }.to raise_error(Llm::SchemaError, /response truncated — hit max_tokens/)
    end

    it "raises Llm::SchemaError when message content is not valid JSON" do
      allow(openai_double).to receive(:chat).and_return(
        chat_response(content: "NOT VALID JSON", provider: "ScaleDown")
      )

      expect {
        @adapter.generate_entity_extraction(model: @extract_model, content: @content, entities: @entities)
      }.to raise_error(Llm::SchemaError, /failed to parse JSON content/)
    end

    it "raises Llm::SchemaError when parsed JSON is not a Hash" do
      allow(openai_double).to receive(:chat).and_return(
        chat_response(content: [1, 2, 3].to_json, provider: "ScaleDown")
      )

      expect {
        @adapter.generate_entity_extraction(model: @extract_model, content: @content, entities: @entities)
      }.to raise_error(Llm::SchemaError, /expected Hash of extracted entities, got Array/)
    end

    it "transforms symbol entity keys to string keys in provider options" do
      mixed_entities = {
        :symbol_key => "Description 1",
        "string_key" => "Description 2"
      }

      expect(openai_double).to receive(:chat) do |parameters:|
        params = parameters.dig(:parameters) || parameters
        expect(params.dig(:provider, :options, :scaledown, :entities)).to eq(
          "symbol_key" => "Description 1",
          "string_key" => "Description 2"
        )
        chat_response(content: {"symbol_key" => "val1", "string_key" => "val2"}.to_json, provider: "ScaleDown")
      end

      @adapter.generate_entity_extraction(model: @extract_model, content: @content, entities: mixed_entities)
    end

    it "handles multiline, unicode, and multi-byte text content without corruption" do
      multibyte_content = "代表者: 山田 太郎 — Directrice: Hélène Dupont — 100% committed to Clean Water."
      expect(openai_double).to receive(:chat) do |parameters:|
        params = parameters.dig(:parameters) || parameters
        expect(params[:messages]).to eq([{role: "user", content: multibyte_content}])
        chat_response(content: {"person" => "山田 太郎"}.to_json, provider: "ScaleDown")
      end

      result = @adapter.generate_entity_extraction(
        model: @extract_model,
        content: multibyte_content,
        entities: {person: "Extracted person name"}
      )
      expect(result).to eq({"person" => "山田 太郎"})
    end

    it "raises ArgumentError when an entity description is nil, whitespace, or non-String object" do
      [nil, "", "   \t\n  ", 12345].each do |bad_desc|
        expect {
          @adapter.generate_entity_extraction(
            model: @extract_model,
            content: @content,
            entities: {name: bad_desc}
          )
        }.to raise_error(ArgumentError, /entity description for :name must be a non-blank String/)
      end
    end

    it "raises ArgumentError when an entity key is empty, whitespace, or non-string/symbol type" do
      ["", "   ", 123].each do |bad_key|
        expect {
          @adapter.generate_entity_extraction(
            model: @extract_model,
            content: @content,
            entities: {bad_key => "Valid description"}
          )
        }.to raise_error(ArgumentError, /entity key must be a non-blank String or Symbol/)
      end
    end

    it "raises Llm::SchemaError when message content is a JSON primitive string or integer" do
      ["\"just a plain string\"", "42"].each do |primitive_json|
        allow(openai_double).to receive(:chat).and_return(
          chat_response(content: primitive_json, provider: "ScaleDown")
        )

        expect {
          @adapter.generate_entity_extraction(model: @extract_model, content: @content, entities: @entities)
        }.to raise_error(Llm::SchemaError, /expected Hash of extracted entities, got /)
      end
    end

    it "raises Llm::TransportError when response choices array is empty or missing" do
      allow(openai_double).to receive(:chat).and_return({"choices" => [], "model" => @extract_model, "provider" => "ScaleDown"})

      expect {
        @adapter.generate_entity_extraction(model: @extract_model, content: @content, entities: @entities)
      }.to raise_error(Llm::TransportError, /malformed response envelope/)

      allow(openai_double).to receive(:chat).and_return({"model" => @extract_model, "provider" => "ScaleDown"})

      expect {
        @adapter.generate_entity_extraction(model: @extract_model, content: @content, entities: @entities)
      }.to raise_error(Llm::TransportError, /malformed response envelope/)
    end

    it "raises UnpinnedUpstreamError when serving company attribution is completely absent or unselected" do
      unattributed = {
        "choices" => [
          {"message" => {"content" => @extracted_json}, "finish_reason" => "stop"}
        ],
        "model" => @extract_model
      }
      allow(openai_double).to receive(:chat).and_return(unattributed)

      expect {
        @adapter.generate_entity_extraction(model: @extract_model, content: @content, entities: @entities)
      }.to raise_error(Llm::OpenRouterAdapter::UnpinnedUpstreamError, /omitted serving upstream company attribution/)

      unselected = chat_response(content: @extracted_json, provider: "ScaleDown")
      unselected["openrouter_metadata"]["endpoints"]["available"].first["selected"] = false
      allow(openai_double).to receive(:chat).and_return(unselected)

      expect {
        @adapter.generate_entity_extraction(model: @extract_model, content: @content, entities: @entities)
      }.to raise_error(Llm::OpenRouterAdapter::UnpinnedUpstreamError, /omitted serving upstream company attribution/)
    end

    it "handles large content bodies and complex multi-key entity schemas" do
      large_text = ("The General Assembly finds and declares that environmental justice requires equal protection. " * 50) +
        "Dr. Evelyn Vance, Chief Scientist at Chesapeake Bay Foundation, presented findings."

      complex_entities = {
        witness_name: "The full name of the testifying witness",
        witness_title: "The professional title of the witness",
        organization: "The entity or group represented by the witness"
      }

      expected_result = {
        "witness_name" => "Dr. Evelyn Vance",
        "witness_title" => "Chief Scientist",
        "organization" => "Chesapeake Bay Foundation"
      }

      expect(openai_double).to receive(:chat) do |parameters:|
        params = parameters.dig(:parameters) || parameters
        expect(params[:max_tokens]).to eq(2048)
        chat_response(content: expected_result.to_json, provider: "ScaleDown")
      end

      result = @adapter.generate_entity_extraction(
        model: @extract_model,
        content: large_text,
        entities: complex_entities,
        max_tokens: 2048
      )

      expect(result).to eq(expected_result)
      expect(@adapter.last_upstream_company).to eq("ScaleDown")
    end

    it "classifies Faraday::TimeoutError and Faraday::ConnectionFailed as transport errors" do
      allow(openai_double).to receive(:chat).and_raise(Faraday::TimeoutError.new("execution expired"))

      expect {
        @adapter.generate_entity_extraction(model: @extract_model, content: @content, entities: @entities)
      }.to raise_error(Llm::TransportError, /openrouter transport: routing service: Faraday::TimeoutError/)

      allow(openai_double).to receive(:chat).and_raise(Faraday::ConnectionFailed.new("connection refused"))

      expect {
        @adapter.generate_entity_extraction(model: @extract_model, content: @content, entities: @entities)
      }.to raise_error(Llm::TransportError, /openrouter transport: routing service: Faraday::ConnectionFailed/)
    end

    it "raises Llm::TransportError when response content is empty" do
      allow(openai_double).to receive(:chat).and_return(
        chat_response(content: "   ", provider: "ScaleDown")
      )

      expect {
        @adapter.generate_entity_extraction(model: @extract_model, content: @content, entities: @entities)
      }.to raise_error(Llm::TransportError, /empty response/)
    end
  end
end
