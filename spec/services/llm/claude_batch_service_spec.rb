# frozen_string_literal: true

require "rails_helper"

# lat:ignore — excludes "an Llm structured-output adapter" (spec/support/shared_examples/llm_structured_output_adapter.rb): those hooks assume raise-on-failure single-call semantics; .results returns non-raising Result structs instead.
RSpec.describe Llm::ClaudeBatchService do
  let(:prompt) do
    Llm::PromptPayload.new(
      system_prompt: "STABLE SYSTEM PROMPT",
      user_message: "PER-BILL USER MESSAGE"
    )
  end
  let(:model) { "claude-sonnet-5-5" }
  let(:schema) { BILL_SUMMARY_SCHEMA_HASH }
  let(:item) do
    described_class::Item.new(
      custom_id: "25-0064__summary",
      prompt: prompt,
      model: model,
      schema: schema,
      validation_schema: BILL_SUMMARY_SCHEMA
    )
  end

  let(:client_double) { instance_double(Anthropic::Client) }
  let(:messages_double) { instance_double(Anthropic::Resources::Messages) }
  let(:batches_double) { instance_double(Anthropic::Resources::Messages::Batches) }

  around do |example|
    original_key = ENV["ANTHROPIC_API_KEY"]
    ENV["ANTHROPIC_API_KEY"] = "sk-ant-test-key" if original_key.to_s.empty?
    begin
      example.run
    ensure
      ENV["ANTHROPIC_API_KEY"] = original_key
    end
  end

  before do
    described_class.instance_variable_set(:@client, nil)
    allow(Anthropic::Client).to receive(:new).and_return(client_double)
    allow(client_double).to receive(:messages).and_return(messages_double)
    allow(messages_double).to receive(:batches).and_return(batches_double)
  end

  def text_block(text)
    double("ContentBlock", type: "text", text: text)
  end

  def tool_use_block
    double("ToolUseBlock", type: "tool_use")
  end

  def usage_double(input_tokens: 1200, output_tokens: 300, cache_read_input_tokens: 0)
    double(
      "Usage",
      input_tokens: input_tokens,
      output_tokens: output_tokens,
      cache_creation_input_tokens: 0,
      cache_read_input_tokens: cache_read_input_tokens
    )
  end

  def succeeded_result(text: nil, stop_reason: "end_turn", content: nil, usage: usage_double, answered_by: "claude-sonnet-5-20260101")
    message = double(
      "Message", content: content || [text_block(text)], stop_reason: stop_reason,
      usage: usage, model: answered_by
    )
    double("MessageBatchSucceededResult", type: "succeeded", message: message)
  end

  def errored_result(error_type: "invalid_request_error", error_message: "bad request shape")
    inner = double("InvalidRequestError", type: error_type, message: error_message)
    error_response = double("ErrorResponse", error: inner)
    double("MessageBatchErroredResult", type: "errored", error: error_response)
  end

  def canceled_result
    double("MessageBatchCanceledResult", type: "canceled")
  end

  def expired_result
    double("MessageBatchExpiredResult", type: "expired")
  end

  def individual_response(custom_id:, result:)
    double("MessageBatchIndividualResponse", custom_id: custom_id, result: result)
  end

  def valid_payload_json
    {"summary_markdown" => "x", "full_breakdown_markdown" => "y", "draft_org_positions" => []}.to_json
  end

  describe ".submit" do
    it "sends requests with params byte-identical to Llm::ClaudeRequestParams.build (proves the sync/batch bodies match)" do
      expected_params = Llm::ClaudeRequestParams.build(prompt: item.prompt, model: item.model, schema: item.schema)
      batch = double("MessageBatch")
      expect(batches_double).to receive(:create) do |requests:, request_options:|
        expect(requests).to eq([{custom_id: item.custom_id, params: expected_params}])
        expect(request_options).to eq({max_retries: described_class::SUBMIT_MAX_RETRIES})
        batch
      end
      expect(described_class.submit(items: [item])).to eq(batch)
    end

    it "maps every item in the array, in order, to a custom_id/params pair" do
      other = described_class::Item.new(
        custom_id: "25-0065__summary", prompt: prompt, model: model, schema: schema, validation_schema: BILL_SUMMARY_SCHEMA
      )
      expect(batches_double).to receive(:create) do |requests:, request_options:|
        expect(request_options).to eq({max_retries: described_class::SUBMIT_MAX_RETRIES})
        expect(requests.map { |r| r[:custom_id] }).to eq(["25-0064__summary", "25-0065__summary"])
        double("MessageBatch")
      end
      described_class.submit(items: [item, other])
    end

    it "asks the SDK for zero retries, so an accepted-but-unacknowledged submit is never bought twice" do
      expect(described_class::SUBMIT_MAX_RETRIES).to eq(0)
      expect(described_class::DEFAULT_MAX_RETRIES).to be > 0
      expect(batches_double).to receive(:create) do |requests:, request_options:|
        expect(request_options[:max_retries]).to eq(0)
        expect(requests.length).to eq(1)
        double("MessageBatch")
      end
      described_class.submit(items: [item])
    end

    it "translates a top-level Anthropic::Errors::APIConnectionError into Llm::TransportError" do
      allow(batches_double).to receive(:create).and_raise(
        Anthropic::Errors::APIConnectionError.new(url: URI("https://api.anthropic.com/v1/messages/batches"), message: "boom")
      )
      expect { described_class.submit(items: [item]) }.to raise_error(Llm::TransportError, /^claude transport: connection/)
    end

    it "raises ArgumentError naming the offending custom_id, and never calls the API, when a custom_id contains a slash" do
      bad_item = described_class::Item.new(
        custom_id: "25-0064/positions", prompt: prompt, model: model, schema: schema, validation_schema: BILL_SUMMARY_SCHEMA
      )
      expect(batches_double).not_to receive(:create)
      expect { described_class.submit(items: [bad_item]) }.to raise_error(ArgumentError) { |e|
        expect(e.message).to include("25-0064/positions")
        expect(e.message).to include(Llm::BatchCustomId::PATTERN.source)
      }
    end

    it "names every offending custom_id when more than one item is invalid" do
      bad_one = described_class::Item.new(
        custom_id: "25-0064/positions", prompt: prompt, model: model, schema: schema, validation_schema: BILL_SUMMARY_SCHEMA
      )
      bad_two = described_class::Item.new(
        custom_id: "25-0065/summary", prompt: prompt, model: model, schema: schema, validation_schema: BILL_SUMMARY_SCHEMA
      )
      expect(batches_double).not_to receive(:create)
      expect { described_class.submit(items: [bad_one, bad_two]) }.to raise_error(ArgumentError) { |e|
        expect(e.message).to include("25-0064/positions")
        expect(e.message).to include("25-0065/summary")
      }
    end
  end

  describe ".status" do
    it "uses .retrieve, not .create or .results_streaming" do
      batch = double("MessageBatch")
      expect(batches_double).to receive(:retrieve).with("batch_123").and_return(batch)
      expect(described_class.status(batch_id: "batch_123")).to eq(batch)
    end
  end

  describe ".cancel" do
    it "uses .cancel with the batch id" do
      batch = double("MessageBatch")
      expect(batches_double).to receive(:cancel).with("batch_123").and_return(batch)
      expect(described_class.cancel(batch_id: "batch_123")).to eq(batch)
    end
  end

  describe ".results" do
    it "uses .results_streaming — the gem has no .results method" do
      expect(batches_double).to receive(:results_streaming)
        .with("batch_123", request_options: {timeout: described_class::BATCH_RESULTS_TIMEOUT_SECONDS})
        .and_return([])
      described_class.results(batch_id: "batch_123", items_by_custom_id: {})
    end

    it "reads results with the batch results-read timeout, not the synchronous one" do
      expect(described_class::BATCH_RESULTS_TIMEOUT_SECONDS).not_to eq(described_class::DEFAULT_TIMEOUT_SECONDS)
      expect(batches_double).to receive(:results_streaming) do |_batch_id, request_options:|
        expect(request_options).to eq({timeout: Llm::ClaudeConnection::BATCH_RESULTS_TIMEOUT_SECONDS})
        []
      end
      described_class.results(batch_id: "batch_123", items_by_custom_id: {})
    end

    it "keys results by custom_id, not by array position (results arrive in arbitrary order)" do
      item_a = described_class::Item.new(
        custom_id: "a", prompt: prompt, model: model, schema: schema, validation_schema: BILL_SUMMARY_SCHEMA
      )
      item_b = described_class::Item.new(
        custom_id: "b", prompt: prompt, model: model, schema: schema, validation_schema: BILL_SUMMARY_SCHEMA
      )
      response_b = individual_response(custom_id: "b", result: succeeded_result(text: valid_payload_json))
      response_a = individual_response(custom_id: "a", result: succeeded_result(text: valid_payload_json))
      allow(batches_double).to receive(:results_streaming).and_return([response_b, response_a])

      results = described_class.results(batch_id: "batch_123", items_by_custom_id: {"a" => item_a, "b" => item_b})

      expect(results.keys).to contain_exactly("a", "b")
      expect(results["a"].custom_id).to eq("a")
      expect(results["b"].custom_id).to eq("b")
    end

    it "delivers an unrecognized custom_id as an errored Result rather than raising KeyError" do
      response = individual_response(custom_id: "gone", result: succeeded_result(text: valid_payload_json))
      allow(batches_double).to receive(:results_streaming).and_return([response])

      results = described_class.results(batch_id: "batch_123", items_by_custom_id: {})

      expect(results["gone"].value).to be_nil
      expect(results["gone"].error).to be_a(Llm::TransportError)
      expect(results["gone"].error.message).to include("unknown custom_id")
    end

    it "still delivers the items it does recognize alongside one it does not" do
      known = individual_response(custom_id: item.custom_id, result: succeeded_result(text: valid_payload_json))
      unknown = individual_response(custom_id: "gone", result: succeeded_result(text: valid_payload_json))
      allow(batches_double).to receive(:results_streaming).and_return([unknown, known])

      results = described_class.results(batch_id: "batch_123", items_by_custom_id: {item.custom_id => item})

      expect(results[item.custom_id].value).to eq(JSON.parse(valid_payload_json))
      expect(results["gone"].error).to be_a(Llm::TransportError)
    end

    it "leaves the SDK retry budget alone on the results read, which is free and idempotent" do
      expect(batches_double).to receive(:results_streaming) do |_batch_id, request_options:|
        expect(request_options).not_to have_key(:max_retries)
        []
      end
      described_class.results(batch_id: "batch_123", items_by_custom_id: {})
    end

    it "delivers the rest of the batch when one item's envelope cannot be mapped" do
      other = described_class::Item.new(
        custom_id: "25-0065__summary", prompt: prompt, model: model, schema: schema, validation_schema: BILL_SUMMARY_SCHEMA
      )
      # result.error.error is dereferenced two levels down
      unmappable = double("MessageBatchErroredResult", type: "errored", error: nil)
      allow(batches_double).to receive(:results_streaming).and_return(
        [
          individual_response(custom_id: item.custom_id, result: unmappable),
          individual_response(custom_id: other.custom_id, result: succeeded_result(text: valid_payload_json))
        ]
      )

      results = described_class.results(
        batch_id: "batch_123",
        items_by_custom_id: {item.custom_id => item, other.custom_id => other}
      )

      expect(results.keys).to contain_exactly(item.custom_id, other.custom_id)
      expect(results[other.custom_id].value).to eq(JSON.parse(valid_payload_json))
      expect(results[other.custom_id].error).to be_nil
      expect(results[item.custom_id].value).to be_nil
      expect(results[item.custom_id].usage).to be_nil
      expect(results[item.custom_id].model).to be_nil
      expect(results[item.custom_id].error).to be_a(Llm::TransportError)
      expect(results[item.custom_id].error.message).to include("NoMethodError")
    end

    it "translates a top-level Anthropic::Errors::RateLimitError into Llm::TransportError" do
      err = Anthropic::Errors::RateLimitError.new(
        url: URI("https://api.anthropic.com/v1/messages/batches/batch_123/results"),
        status: 429,
        headers: {}, #: Hash[String, untyped]
        body: nil,
        request: nil,
        response: nil,
        message: "rate-limited"
      )
      allow(batches_double).to receive(:results_streaming).and_raise(err)
      expect {
        described_class.results(batch_id: "batch_123", items_by_custom_id: {})
      }.to raise_error(Llm::TransportError, /^claude transport: 429 rate_limit/)
    end

    describe "per-item result mapping" do
      def one_result(result)
        allow(batches_double).to receive(:results_streaming).and_return([individual_response(custom_id: item.custom_id, result: result)])
        described_class.results(batch_id: "batch_123", items_by_custom_id: {item.custom_id => item}).fetch(item.custom_id)
      end

      it "maps stop_reason max_tokens to a Result with a discardable Llm::SchemaError (truncated)" do
        mapped = one_result(succeeded_result(text: "irrelevant", stop_reason: "max_tokens"))
        expect(mapped.value).to be_nil
        expect(mapped.error).to be_a(Llm::SchemaError)
        expect(mapped.error.message).to match(/truncated/)
      end

      it "maps a missing text content block to a Result with Llm::TransportError (unexpected response shape)" do
        mapped = one_result(succeeded_result(content: [tool_use_block]))
        expect(mapped.value).to be_nil
        expect(mapped.error).to be_a(Llm::TransportError)
        expect(mapped.error.message).to match(/unexpected response shape/)
      end

      it "maps blank text to a Result with Llm::TransportError (empty response)" do
        mapped = one_result(succeeded_result(text: ""))
        expect(mapped.error).to be_a(Llm::TransportError)
        expect(mapped.error.message).to match(/empty response/)
      end

      it "maps a schema-invalid payload to a Result with a rescued Llm::SchemaError, not a raise" do
        mapped = one_result(succeeded_result(text: {"only_key" => "value"}.to_json))
        expect(mapped.value).to be_nil
        expect(mapped.error).to be_a(Llm::SchemaError)
      end

      it "maps a valid succeeded payload to a Result with value set and error nil" do
        mapped = one_result(succeeded_result(text: valid_payload_json))
        expect(mapped.value).to eq(JSON.parse(valid_payload_json))
        expect(mapped.error).to be_nil
      end

      it "carries the message usage on a succeeded Result so callers need no second results fetch" do
        usage = usage_double(input_tokens: 4321, output_tokens: 210, cache_read_input_tokens: 4000)
        mapped = one_result(succeeded_result(text: valid_payload_json, usage: usage))
        expect(mapped.usage.input_tokens).to eq(4321)
        expect(mapped.usage.output_tokens).to eq(210)
        expect(mapped.usage.cache_read_input_tokens).to eq(4000)
      end

      it "carries the model that actually answered, which the request only asked for" do
        mapped = one_result(succeeded_result(text: valid_payload_json, answered_by: "claude-sonnet-5-20260101"))
        expect(mapped.model).to eq("claude-sonnet-5-20260101")
      end

      it "leaves model nil on a non-succeeded Result" do
        expect(one_result(errored_result).model).to be_nil
        expect(one_result(canceled_result).model).to be_nil
        expect(one_result(expired_result).model).to be_nil
      end

      it "leaves usage nil on a non-succeeded Result" do
        expect(one_result(errored_result).usage).to be_nil
        expect(one_result(succeeded_result(text: "irrelevant", stop_reason: "max_tokens")).usage).to be_nil
      end

      it "maps an errored result via the double-nested result.error.error.type/.message" do
        mapped = one_result(errored_result(error_type: "invalid_request_error", error_message: "bad request shape"))
        expect(mapped.value).to be_nil
        expect(mapped.error).to be_a(Llm::TransportError)
        expect(mapped.error.message).to include("invalid_request_error")
        expect(mapped.error.message).to include("bad request shape")
      end

      it "maps a canceled result to a Result with Llm::TransportError 'item canceled'" do
        mapped = one_result(canceled_result)
        expect(mapped.error).to be_a(Llm::TransportError)
        expect(mapped.error.message).to match(/item canceled/)
      end

      it "maps an expired result to a Result with Llm::TransportError 'item expired (batch exceeded 24h)'" do
        mapped = one_result(expired_result)
        expect(mapped.error).to be_a(Llm::TransportError)
        expect(mapped.error.message).to match(/item expired \(batch exceeded 24h\)/)
      end

      it "maps an unrecognized result type to a Result with Llm::TransportError 'unknown result type'" do
        mapped = one_result(double("SomeFutureResult", type: "something_new"))
        expect(mapped.error).to be_a(Llm::TransportError)
        expect(mapped.error.message).to match(/unknown result type/)
      end
    end
  end
end
