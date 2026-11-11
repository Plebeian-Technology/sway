# frozen_string_literal: true

require "rails_helper"

# Llm::LlamacppAdapter wraps ruby-openai and points it at the local
# llama.cpp /v1/chat/completions endpoint. Checks the chat request shape
# and how errors turn into our own classes.
RSpec.describe Llm::LlamacppAdapter do
  let(:prompt) do
    Llm::PromptPayload.new(
      system_prompt: "STABLE SYSTEM PROMPT",
      user_message: "PER-BILL USER MESSAGE"
    )
  end
  let(:model) { "local" }
  let(:schema) { BILL_SUMMARY_SCHEMA_HASH }
  let(:openai_double) { instance_double(OpenAI::Client) }

  before do
    allow(OpenAI::Client).to receive(:new).and_return(openai_double)
  end

  def chat_response(*_args, **kwargs)
    content = kwargs.fetch(:content)
    finish_reason = kwargs.fetch(:finish_reason, "stop")
    {
      "choices" => [
        {
          "message" => {"content" => content},
          "finish_reason" => finish_reason
        }
      ]
    }
  end

  def valid_payload_json
    {
      "summary_markdown" => "x",
      "full_breakdown_markdown" => "y",
      "draft_org_positions" => [] #: Array[untyped]
    }.to_json
  end

  # The four hooks the shared contract calls. Their Claude twins live at the
  # same place in claude_adapter_spec.rb, so the one group below runs against
  # both adapters and neither can be changed alone.
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
    it "returns 'llamacpp'" do
      expect(described_class.new.provider_label).to eq("llamacpp")
    end
  end

  # @lat: [[llamacpp-adapter-design#.request_timeout_seconds: why 120s assumes an immediate-answering model]]
  describe ".request_timeout_seconds" do
    it "takes the deadline from the setting" do
      with_app_config(:llm, llm_request_timeout_seconds: 900) do
        expect(described_class.request_timeout_seconds).to eq(900)
      end
    end

    # @lat: [[llamacpp-adapter-design#.request_timeout_seconds: why 120s assumes an immediate-answering model]]
    it "falls back to the default when the setting is zero or negative" do
      [0, -30].each do |bad_value|
        with_app_config(:llm, llm_request_timeout_seconds: bad_value) do
          expect(described_class.request_timeout_seconds)
            .to eq(Sway::Settings::Llm.defaults.fetch("llm_request_timeout_seconds")),
              "expected #{bad_value.inspect} to fall back to the default"
        end
      end
    end

    it "defaults to 120 seconds when the setting is unset" do
      with_app_config(:llm, llm_request_timeout_seconds: nil) do
        expect(described_class.request_timeout_seconds).to eq(120)
      end
    end
  end

  # @lat: [[llm-summaries#LLM bill summaries#Two adapters, one client#What the local server is asked for, and how long it is given]]
  describe "the thinking flag the request carries" do
    it "asks the chat template not to think, by default" do
      stub_adapter_body(valid_payload_json)

      with_app_config(:llm, llm_llamacpp_thinking: nil) { run_structured_call }

      expect(openai_double).to have_received(:chat).with(
        parameters: hash_including(chat_template_kwargs: {enable_thinking: false})
      )
    end

    it "puts thinking back when the setting is on" do
      stub_adapter_body(valid_payload_json)

      with_app_config(:llm, llm_llamacpp_thinking: true) { run_structured_call }

      expect(openai_double).to have_received(:chat).with(
        parameters: hash_including(chat_template_kwargs: {enable_thinking: true})
      )
    end

    # @lat: [[llamacpp-adapter-design#.thinking_enabled?: asking the chat template not to think first]]
    it "turns thinking on for words wider than the old '1'-only comparison" do
      %w[true yes y t].each do |value|
        with_env("LLM_LLAMACPP_THINKING" => value) do
          expect(Sway::Settings::Llm.new.llm_llamacpp_thinking).to be(true),
            "expected #{value.inspect} to switch thinking on"
        end
      end
    end

    it "still leaves thinking off for text the caster does not recognise" do
      ["", "0", "off", "maybe"].each do |value|
        with_env("LLM_LLAMACPP_THINKING" => value) do
          expect(Sway::Settings::Llm.new.llm_llamacpp_thinking).to be(false),
            "expected #{value.inspect} to leave thinking off"
        end
      end
    end
  end

  describe "the deadline the request carries" do
    it "hands the setting to the OpenAI client" do
      stub_adapter_body(valid_payload_json)

      with_app_config(:llm, llm_request_timeout_seconds: 900) do
        run_structured_call
      end

      expect(OpenAI::Client).to have_received(:new)
        .with(hash_including(request_timeout: 900))
    end

    it "hands the default to the OpenAI client when the setting is unset" do
      stub_adapter_body(valid_payload_json)

      with_app_config(:llm, llm_request_timeout_seconds: nil) do
        run_structured_call
      end

      expect(OpenAI::Client).to have_received(:new)
        .with(hash_including(request_timeout: 120))
    end
  end

  describe "the local model server address" do
    it "hands the setting to the OpenAI client's uri_base" do
      stub_adapter_body(valid_payload_json)

      with_app_config(:llm, llamacpp_base_url: "http://example.test/v1") do
        run_structured_call
      end

      expect(OpenAI::Client).to have_received(:new)
        .with(hash_including(uri_base: "http://example.test/v1"))
    end
  end

  describe "#generate_bill_summary — happy path" do
    it "returns the parsed Hash and validates against BILL_SUMMARY_SCHEMA" do
      allow(openai_double).to receive(:chat).and_return(chat_response(content: valid_payload_json))
      result = described_class.new.generate_bill_summary(prompt: prompt, model: model, schema: schema)
      expect(result).to be_a(Hash)
      expect(result.keys).to include("summary_markdown", "full_breakdown_markdown", "draft_org_positions")
    end

    it "sends messages with the system+user split and response_format json_schema strict" do
      expect(openai_double).to receive(:chat) do |parameters:|
        expect(parameters[:messages]).to eq(
          [
            {role: "system", content: "STABLE SYSTEM PROMPT"},
            {role: "user", content: "PER-BILL USER MESSAGE"}
          ]
        )
        rf = parameters[:response_format]
        expect(rf[:type]).to eq("json_schema")
        expect(rf[:json_schema][:schema]).to eq(BILL_SUMMARY_SCHEMA_HASH)
        expect(rf[:json_schema][:strict]).to eq(true)
        chat_response(content: valid_payload_json)
      end
      described_class.new.generate_bill_summary(prompt: prompt, model: model, schema: schema)
    end
  end

  describe "error translation" do
    it "raises Llm::TransportError on Faraday::Error (prefix preserved for log grep readability)" do
      allow(openai_double).to receive(:chat).and_raise(Faraday::ConnectionFailed.new("connection refused"))
      expect {
        described_class.new.generate_bill_summary(prompt: prompt, model: model, schema: schema)
      }.to raise_error(Llm::TransportError, /^llama.cpp transport:/)
    end

    it "raises Llm::TransportError on OpenAI::Error" do
      allow(openai_double).to receive(:chat).and_raise(OpenAI::Error.new("boom"))
      expect {
        described_class.new.generate_bill_summary(prompt: prompt, model: model, schema: schema)
      }.to raise_error(Llm::TransportError, /^llama.cpp transport:/)
    end

    it "raises Llm::SchemaError on malformed JSON ('Malformed JSON from llama.cpp:')" do
      allow(openai_double).to receive(:chat).and_return(chat_response(content: "{not valid json"))
      expect {
        described_class.new.generate_bill_summary(prompt: prompt, model: model, schema: schema)
      }.to raise_error(Llm::SchemaError, /^Malformed JSON from llama.cpp/)
    end

    it "raises Llm::SchemaError on schema-violation ('Schema validation failed:')" do
      allow(openai_double).to receive(:chat).and_return(chat_response(content: {"only_key" => "value"}.to_json))
      expect {
        described_class.new.generate_bill_summary(prompt: prompt, model: model, schema: schema)
      }.to raise_error(Llm::SchemaError, /^Schema validation failed/)
    end

    it "raises Llm::TransportError on empty response" do
      allow(openai_double).to receive(:chat).and_return(chat_response(content: ""))
      expect {
        described_class.new.generate_bill_summary(prompt: prompt, model: model, schema: schema)
      }.to raise_error(Llm::TransportError, /^llama.cpp transport:/)
    end

    # @lat: [[llm-adapter-shared-contract-drift#Why the LLM adapter error-classification shared example exists]]
    ["\n", "   ", "\n\n  \t"].each do |blank|
      it "raises Llm::TransportError on a response of only whitespace (#{blank.inspect})" do
        allow(openai_double).to receive(:chat).and_return(chat_response(content: blank))
        expect {
          described_class.new.generate_bill_summary(prompt: prompt, model: model, schema: schema)
        }.to raise_error(Llm::TransportError, /^llama.cpp transport:/)
      end
    end

    # Same reclassification as the Claude adapter: hitting the token cap
    # fails the same way every time, so retrying pays three times for a
    # guaranteed repeat.
    it "raises Llm::SchemaError when finish_reason is 'length' (max_tokens truncation)" do
      allow(openai_double).to receive(:chat).and_return(
        chat_response(content: valid_payload_json, finish_reason: "length")
      )
      expect {
        described_class.new.generate_bill_summary(prompt: prompt, model: model, schema: schema)
      }.to raise_error(Llm::SchemaError, /^llama.cpp schema:.*truncated/)
    end
  end

  describe "#generate_bill_categories" do
    let(:categories_schema) { BILL_CATEGORIES_SCHEMA_HASH }

    def valid_categories_json
      {"categories" => ["Health", "Environment"]}.to_json
    end

    def four_item_categories_json
      {"categories" => ["A", "B", "C", "D"]}.to_json
    end

    def empty_categories_json
      {"categories" => []}.to_json
    end

    it "happy path: returns parsed {'categories' => [...]} Hash for a well-formed response" do
      allow(openai_double).to receive(:chat).and_return(chat_response(content: valid_categories_json))
      result = described_class.new.generate_bill_categories(
        prompt: prompt, model: model, schema: categories_schema
      )
      expect(result).to be_a(Hash)
      expect(result["categories"]).to eq(["Health", "Environment"])
    end

    # See the matching comment in claude_adapter_spec.rb: both share
    # Llm::SchemaValidator, so both trim a fixable overshoot instead of
    # discarding the response. Keeping the two identical is the point.
    it "degrades a 4-item array to the schema's maxItems instead of discarding the response" do
      allow(openai_double).to receive(:chat).and_return(chat_response(content: four_item_categories_json))

      result = described_class.new.generate_bill_categories(
        prompt: prompt, model: model, schema: categories_schema
      )

      expect(result["categories"].length).to eq(3)
    end

    # The llama.cpp half of the same problem: the original report named
    # only claude_adapter.rb, but this adapter hands over the same control
    # on the very same line of its own generate_structured.
    it "normalizes against the boot schema, not against a caller-supplied hash" do
      hostile = BILL_CATEGORIES_SCHEMA_HASH.deep_dup
      hostile["properties"]["categories"]["maxItems"] = 1
      allow(openai_double).to receive(:chat).and_return(chat_response(content: valid_categories_json))

      result = described_class.new.generate_bill_categories(
        prompt: prompt, model: model, schema: hostile
      )

      expect(result["categories"]).to eq(["Health", "Environment"])
    end

    it "raises Llm::SchemaError for an empty array response (minItems:1 violated)" do
      allow(openai_double).to receive(:chat).and_return(chat_response(content: empty_categories_json))
      expect {
        described_class.new.generate_bill_categories(
          prompt: prompt, model: model, schema: categories_schema
        )
      }.to raise_error(Llm::SchemaError)
    end

    it "raises Llm::TransportError on Faraday::Error" do
      allow(openai_double).to receive(:chat).and_raise(Faraday::ConnectionFailed.new("connection refused"))
      expect {
        described_class.new.generate_bill_categories(
          prompt: prompt, model: model, schema: categories_schema
        )
      }.to raise_error(Llm::TransportError, /^llama.cpp transport:/)
    end

    it "raises Llm::TransportError on OpenAI::Error" do
      allow(openai_double).to receive(:chat).and_raise(OpenAI::Error.new("boom"))
      expect {
        described_class.new.generate_bill_categories(
          prompt: prompt, model: model, schema: categories_schema
        )
      }.to raise_error(Llm::TransportError, /^llama.cpp transport:/)
    end
  end

  # A positions-only LLM pass over testimony. It goes through the shared
  # generate_structured and always validates with BILL_POSITIONS_SCHEMA,
  # no matter which schema the caller passes.
  describe "#generate_bill_positions" do
    let(:positions_schema) { BILL_POSITIONS_SCHEMA_HASH }

    def valid_positions_json
      {
        "draft_org_positions" => [
          {"org_name" => "ACLU", "stance" => "support", "summary" => "Protects rights."}
        ]
      }.to_json
    end

    # This used to be an ambiguous payload breaking BOTH schemas. This one
    # passes BILL_SUMMARY_SCHEMA and fails BILL_POSITIONS_SCHEMA, failing
    # only if positions is the one validating.
    def summary_shaped_positions_json
      {
        "summary_markdown" => "A valid summary body.",
        "full_breakdown_markdown" => "A valid breakdown body."
      }.to_json
    end

    it "happy path: returns the parsed, schema-validated Hash" do
      allow(openai_double).to receive(:chat).and_return(chat_response(content: valid_positions_json))
      result = described_class.new.generate_bill_positions(
        prompt: prompt, model: model, schema: positions_schema
      )
      expect(result).to be_a(Hash)
      expect(BILL_POSITIONS_SCHEMA.validate(result).to_a).to be_empty
    end

    it "sends response_format json_schema with name 'bill_positions'" do
      expect(openai_double).to receive(:chat) do |parameters:|
        rf = parameters[:response_format]
        expect(rf[:json_schema][:name]).to eq("bill_positions")
        expect(rf[:json_schema][:schema]).to eq(positions_schema)
        chat_response(content: valid_positions_json)
      end
      described_class.new.generate_bill_positions(prompt: prompt, model: model, schema: positions_schema)
    end

    it "raises Llm::SchemaError for a payload that BILL_SUMMARY_SCHEMA would accept (proves BILL_POSITIONS_SCHEMA is wired)" do
      allow(openai_double).to receive(:chat).and_return(chat_response(content: summary_shaped_positions_json))
      expect {
        described_class.new.generate_bill_positions(
          prompt: prompt, model: model, schema: positions_schema
        )
      }.to raise_error(Llm::SchemaError)
    end

    it "raises Llm::TransportError on Faraday::Error" do
      allow(openai_double).to receive(:chat).and_raise(Faraday::ConnectionFailed.new("connection refused"))
      expect {
        described_class.new.generate_bill_positions(
          prompt: prompt, model: model, schema: positions_schema
        )
      }.to raise_error(Llm::TransportError, /^llama.cpp transport:/)
    end
  end

  # The dev-and-test half of the same gap: no adapter-level tests existed
  # on EITHER adapter, so a wrong schema name would ship unnoticed — and
  # this is the adapter offline classification uses.
  describe "#generate_testimony_classification" do
    let(:classification_schema) { TESTIMONY_CLASSIFICATION_SCHEMA_HASH }

    def valid_classification_json
      {
        "classifications" => [
          {"index" => 0, "label" => "testimony"},
          {"index" => 1, "label" => "not_testimony"}
        ]
      }.to_json
    end

    # This payload passes BILL_POSITIONS_SCHEMA and fails
    # TESTIMONY_CLASSIFICATION_SCHEMA. The ClaudeAdapter spec explains why that
    # split is the thing that catches this particular copy-paste slip.
    def positions_shaped_classification_json
      {"draft_org_positions" => []}.to_json
    end

    it "happy path: returns the parsed, schema-validated Hash" do
      allow(openai_double).to receive(:chat).and_return(chat_response(content: valid_classification_json))
      result = described_class.new.generate_testimony_classification(
        prompt: prompt, model: model, schema: classification_schema
      )
      expect(result).to be_a(Hash)
      expect(TESTIMONY_CLASSIFICATION_SCHEMA.validate(result).to_a).to be_empty
    end

    it "sends response_format json_schema with name 'testimony_classification'" do
      expect(openai_double).to receive(:chat) do |parameters:|
        rf = parameters[:response_format]
        expect(rf[:json_schema][:name]).to eq("testimony_classification")
        expect(rf[:json_schema][:schema]).to eq(classification_schema)
        chat_response(content: valid_classification_json)
      end
      described_class.new.generate_testimony_classification(
        prompt: prompt, model: model, schema: classification_schema
      )
    end

    it "raises Llm::SchemaError for a payload that BILL_POSITIONS_SCHEMA would accept (proves TESTIMONY_CLASSIFICATION_SCHEMA is wired)" do
      allow(openai_double).to receive(:chat)
        .and_return(chat_response(content: positions_shaped_classification_json))
      expect {
        described_class.new.generate_testimony_classification(
          prompt: prompt, model: model, schema: classification_schema
        )
      }.to raise_error(Llm::SchemaError)
    end

    it "raises Llm::TransportError on Faraday::Error" do
      allow(openai_double).to receive(:chat).and_raise(Faraday::ConnectionFailed.new("connection refused"))
      expect {
        described_class.new.generate_testimony_classification(
          prompt: prompt, model: model, schema: classification_schema
        )
      }.to raise_error(Llm::TransportError, /^llama.cpp transport:/)
    end
  end

  describe "#generate_news_claim_grounding" do
    let(:grounding_schema) { NEWS_CLAIM_GROUNDING_SCHEMA_HASH }

    def valid_grounding_json
      {"verdict" => "supported", "reason" => "Grounding corroborated."}.to_json
    end

    it "happy path: returns parsed, schema-validated Hash" do
      allow(openai_double).to receive(:chat).and_return(chat_response(content: valid_grounding_json))
      result = described_class.new.generate_news_claim_grounding(
        prompt: prompt, model: model, schema: grounding_schema
      )
      expect(result).to eq({"verdict" => "supported", "reason" => "Grounding corroborated."})
    end

    it "raises Llm::SchemaError for invalid schema payload" do
      allow(openai_double).to receive(:chat).and_return(chat_response(content: {"invalid" => "payload"}.to_json))
      expect {
        described_class.new.generate_news_claim_grounding(
          prompt: prompt, model: model, schema: grounding_schema
        )
      }.to raise_error(Llm::SchemaError)
    end
  end

  describe "#generate_testimony_stance_classification" do
    it "happy path: returns parsed, schema-validated Hash" do
      stance_schema = TESTIMONY_STANCE_CLASSIFICATION_SCHEMA_HASH
      valid_stance_json = {
        "classifications" => [
          {"position" => 0, "stance" => "neutral"}
        ]
      }.to_json

      allow(openai_double).to receive(:chat).and_return(chat_response(content: valid_stance_json))
      result = described_class.new.generate_testimony_stance_classification(
        prompt: prompt, model: model, schema: stance_schema
      )
      expect(result["classifications"].first["stance"]).to eq("neutral")
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
end
