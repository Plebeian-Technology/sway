# frozen_string_literal: true

require "rails_helper"

# Llm::ClaudeAdapter wraps the Anthropic SDK. This spec fakes
# Anthropic::Client/Messages, checking request shape and how SDK errors
# become our own error classes. Nothing calls the real API.
RSpec.describe Llm::ClaudeAdapter do
  let(:prompt) do
    Llm::PromptPayload.new(
      system_prompt: "STABLE SYSTEM PROMPT",
      user_message: "PER-BILL USER MESSAGE"
    )
  end
  let(:model) { "claude-haiku-5-5" }
  let(:schema) { BILL_SUMMARY_SCHEMA_HASH }
  let(:client_double) { instance_double(Anthropic::Client) }
  let(:messages_double) { instance_double(Anthropic::Resources::Messages) }

  # Save ENV["ANTHROPIC_API_KEY"] and restore it after. A leaked placeholder
  # key once crashed the prompt-builder spec via a tokenizer raising
  # AuthenticationError.
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
    allow(Anthropic::Client).to receive(:new).and_return(client_double)
    allow(client_double).to receive(:messages).and_return(messages_double)
  end

  # Builds a fake response the adapter can read. The content block carries
  # type: text since the adapter checks that first. stop_reason defaults to
  # a String, matching the real SDK.
  def make_response(*_args, **kwargs)
    text = kwargs.fetch(:text)
    stop_reason = kwargs.fetch(:stop_reason, "end_turn")
    input_tokens = kwargs.fetch(:input_tokens, 1500)
    output_tokens = kwargs.fetch(:output_tokens, 300)
    content_block = double("ContentBlock", type: "text", text: text)
    usage = double(
      "Usage",
      input_tokens: input_tokens,
      output_tokens: output_tokens,
      cache_creation_input_tokens: 1100,
      cache_read_input_tokens: 0
    )
    double("Response", content: [content_block], stop_reason: stop_reason, usage: usage)
  end

  # Builds a response shaped like a known misfire: the first content block
  # is tool_use, not text, with no .text method — a real production case
  # the adapter must catch and raise clearly.
  def make_tool_use_response(*_args, **_kwargs)
    tool_block = double("ToolUseBlock", type: "tool_use")
    usage = double(
      "Usage",
      input_tokens: 1500,
      output_tokens: 300,
      cache_creation_input_tokens: 1100,
      cache_read_input_tokens: 0
    )
    double("Response", content: [tool_block], stop_reason: "tool_use", usage: usage)
  end

  # A thinking block has no .text method, matching the real SDK shape.
  def make_thinking_block
    double("ThinkingBlock", type: "thinking")
  end

  # @lat: [[explanation/llm-summaries#Talking to the Anthropic SDK#Why the reply is searched for a text block]]
  def make_thinking_then_text_response(*_args, **kwargs)
    text = kwargs.fetch(:text)
    stop_reason = kwargs.fetch(:stop_reason, "end_turn")
    usage = double(
      "Usage",
      input_tokens: 1500,
      output_tokens: 300,
      cache_creation_input_tokens: 1100,
      cache_read_input_tokens: 0
    )
    double("Response", content: [make_thinking_block, double("ContentBlock", type: "text", text: text)], stop_reason: stop_reason, usage: usage)
  end

  def valid_payload_json
    {
      "summary_markdown" => "x",
      "full_breakdown_markdown" => "y",
      "draft_org_positions" => [] #: Array[untyped]
    }.to_json
  end

  # The four hooks the shared contract calls, so an Llm structured-output
  # adapter stays provider-free and runs unchanged against both adapters.
  def stub_adapter_body(body)
    allow(messages_double).to receive(:create).and_return(make_response(text: body))
  end

  def stub_adapter_truncated
    allow(messages_double).to receive(:create)
      .and_return(make_response(text: valid_payload_json, stop_reason: "max_tokens"))
  end

  def stub_adapter_transport
    allow(messages_double).to receive(:create).and_raise(
      Anthropic::Errors::APIConnectionError.new(url: URI("https://api.anthropic.com/v1/messages"), message: "boom")
    )
  end

  def run_structured_call
    described_class.new.generate_bill_summary(prompt: prompt, model: model, schema: schema)
  end

  include_examples "an Llm structured-output adapter"

  describe "#provider_label" do
    it "returns 'claude'" do
      expect(described_class.new.provider_label).to eq("claude")
    end
  end

  describe "#generate_bill_summary — happy path" do
    it "returns the parsed Hash and runs BILL_SUMMARY_SCHEMA.validate (defense in depth)" do
      allow(messages_double).to receive(:create).and_return(make_response(text: valid_payload_json))
      adapter = described_class.new
      result = adapter.generate_bill_summary(prompt: prompt, model: model, schema: schema)
      expect(result).to be_a(Hash)
      expect(result.keys).to include("summary_markdown", "full_breakdown_markdown", "draft_org_positions")
      expect(BILL_SUMMARY_SCHEMA.validate(result).to_a).to be_empty
    end

    it "calls messages.create exactly once with the right kwargs" do
      expect(messages_double).to receive(:create).once.and_return(make_response(text: valid_payload_json))
      described_class.new.generate_bill_summary(prompt: prompt, model: model, schema: schema)
    end

    it "parses the same result when a thinking block precedes the text block" do
      allow(messages_double).to receive(:create).and_return(make_thinking_then_text_response(text: valid_payload_json))
      result = described_class.new.generate_bill_summary(prompt: prompt, model: model, schema: schema)
      expect(result).to eq(JSON.parse(valid_payload_json))
    end
  end

  describe "request kwarg shape (R4 + R5 + GA structured outputs)" do
    it "passes the model and max_tokens 4096, and omits sampling params (Opus 4.7+ reject temperature/top_p/top_k)" do
      expect(messages_double).to receive(:create) do |args|
        expect(args[:model]).to eq(model)
        expect(args[:max_tokens]).to eq(4096)
        expect(args).not_to have_key(:temperature)
        expect(args).not_to have_key(:top_p)
        expect(args).not_to have_key(:top_k)
        make_response(text: valid_payload_json)
      end
      described_class.new.generate_bill_summary(prompt: prompt, model: model, schema: schema)
    end

    # A24-03: passing the 120s ceiling to Client.new got thrown away by the
    # SDK, which builds timeout: 600 by splat order unless set per-request —
    # 120 gave a LONGER deadline than nothing.
    it "carries the per-call deadline as a request option, which is the one the SDK honours" do
      expect(messages_double).to receive(:create) do |args|
        expect(args[:request_options]).to eq({timeout: described_class::DEFAULT_TIMEOUT_SECONDS})
        make_response(text: valid_payload_json)
      end
      described_class.new.generate_bill_summary(prompt: prompt, model: model, schema: schema)
    end

    # Pins the assumption the old client-level setting rested on: the
    # client timeout counts only when it equals the SDK default, and ours
    # deliberately differs.
    it "cannot rely on the client-level timeout, because it is not the SDK default" do
      expect(described_class::DEFAULT_TIMEOUT_SECONDS)
        .not_to eq(Anthropic::Client::DEFAULT_TIMEOUT_IN_SECONDS)
    end

    it "sends the same request-option deadline on every structured call, not just the summary" do
      [
        [:generate_bill_categories, BILL_CATEGORIES_SCHEMA_HASH, {"categories" => ["Housing"]}.to_json],
        [:generate_bill_positions, BILL_POSITIONS_SCHEMA_HASH, {"draft_org_positions" => []}.to_json]
      ].each do |method, call_schema, payload|
        seen = nil #: Hash[Symbol, untyped]?
        allow(messages_double).to receive(:create) do |args|
          seen = args
          make_response(text: payload)
        end

        described_class.new.public_send(method, prompt: prompt, model: model, schema: call_schema)

        expect(seen&.dig(:request_options))
          .to eq({timeout: described_class::DEFAULT_TIMEOUT_SECONDS}), "#{method} did not carry the deadline"
      end
    end

    # The cache marker attaches only when the prefix clears the model's
    # minimum — under that floor it's silently uncached, no error, so
    # attaching it always let a wrong floor belief go unnoticed.
    it "passes system: as an Array with cache_control: {type: 'ephemeral'} when the prefix clears the model floor (R5)" do
      # This long string is not a stand-in for the real prompt — it only
      # checks the adapter's wiring, that a prefix past the floor arrives
      # with cache_control. Real prefixes live in prompt_cache_spec.rb.
      long_prompt = Llm::PromptPayload.new(
        system_prompt: "S" * 7366,
        user_message: "PER-BILL USER MESSAGE"
      )
      expect(messages_double).to receive(:create) do |args|
        expect(args[:system]).to be_an(Array)
        first_block = args[:system].first
        expect(first_block[:type]).to eq("text")
        expect(first_block[:text]).to eq("S" * 7366)
        expect(first_block[:cache_control]).to eq({type: "ephemeral"})
        make_response(text: valid_payload_json)
      end
      described_class.new.generate_bill_summary(prompt: long_prompt, model: "claude-sonnet-5-5", schema: schema)
    end

    it "omits cache_control when the prefix cannot clear the model floor (Haiku 5.5 wants 4096 tokens)" do
      expect(messages_double).to receive(:create) do |args|
        first_block = args[:system].first
        expect(first_block[:type]).to eq("text")
        expect(first_block[:text]).to eq("STABLE SYSTEM PROMPT")
        expect(first_block).not_to have_key(:cache_control)
        make_response(text: valid_payload_json)
      end
      described_class.new.generate_bill_summary(prompt: prompt, model: model, schema: schema)
    end

    it "passes messages: [{role: 'user', content: user_message}]" do
      expect(messages_double).to receive(:create) do |args|
        expect(args[:messages]).to eq([{role: "user", content: "PER-BILL USER MESSAGE"}])
        make_response(text: valid_payload_json)
      end
      described_class.new.generate_bill_summary(prompt: prompt, model: model, schema: schema)
    end

    # The adapter sends output_config.format on the normal endpoint —
    # Anthropic removed the old kwarg, now a 400. The wire schema is
    # trimmed; JSONSchemer still validates the response strictly.
    it "passes output_config.format with type: 'json_schema' and the request-safe BILL_SUMMARY schema" do
      expect(messages_double).to receive(:create) do |args|
        fmt = args.dig(:output_config, :format)
        expect(fmt[:type]).to eq("json_schema")
        expect(fmt[:schema]).to eq(Llm::StructuredOutputSchema.for_request(BILL_SUMMARY_SCHEMA_HASH))
        expect(fmt[:schema]).not_to eq(BILL_SUMMARY_SCHEMA_HASH)
        make_response(text: valid_payload_json)
      end
      described_class.new.generate_bill_summary(prompt: prompt, model: model, schema: schema)
    end

    it "does not send the deprecated output_format kwarg or an anthropic-beta header" do
      expect(messages_double).to receive(:create) do |args|
        expect(args).not_to have_key(:output_format)
        expect(args).not_to have_key(:extra_headers)
        make_response(text: valid_payload_json)
      end
      described_class.new.generate_bill_summary(prompt: prompt, model: model, schema: schema)
    end
  end

  describe "error translation" do
    # The real SDK returns stop_reason as a String, not a Symbol, so the
    # fakes match. Rescues run specific before general, since
    # APITimeoutError subclasses APIConnectionError in some SDK versions.
    let(:anthropic_url) { URI("https://api.anthropic.com/v1/messages") }

    # Hitting max_tokens fails the same way every retry, so it used to pay
    # full cost 3 times before settling failed. SchemaError is the honest
    # name: a truncated response is incomplete JSON anyway.
    it "raises Llm::SchemaError on stop_reason 'max_tokens' (deterministic — the cap does not change on retry)" do
      allow(messages_double).to receive(:create).and_return(make_response(text: "irrelevant", stop_reason: "max_tokens"))
      expect {
        described_class.new.generate_bill_summary(prompt: prompt, model: model, schema: schema)
      }.to raise_error(Llm::SchemaError, /^claude schema: response truncated/)
    end

    it "keeps the operator remedy in the truncation message so generation_error is actionable" do
      allow(messages_double).to receive(:create).and_return(make_response(text: "irrelevant", stop_reason: "max_tokens"))
      expect {
        described_class.new.generate_bill_summary(prompt: prompt, model: model, schema: schema)
      }.to raise_error(Llm::SchemaError, /extend MAX_TOKENS or trim/)
    end

    it "raises Llm::TransportError on empty response content" do
      allow(messages_double).to receive(:create).and_return(make_response(text: ""))
      expect {
        described_class.new.generate_bill_summary(prompt: prompt, model: model, schema: schema)
      }.to raise_error(Llm::TransportError, /^claude transport: empty response/)
    end

    # Structured outputs can put JSON in a tool_use block by mistake.
    # Without an explicit type check, .text raises NoMethodError, uncaught
    # by any rescue, so the row sits in generating forever.
    it "raises Llm::TransportError when first content block is type=tool_use" do
      allow(messages_double).to receive(:create).and_return(make_tool_use_response)
      expect {
        described_class.new.generate_bill_summary(prompt: prompt, model: model, schema: schema)
      }.to raise_error(Llm::TransportError, /unexpected response shape.*tool_use.*output_config\.format/m)
    end

    it "raises Llm::TransportError when response.content is empty" do
      # A String stop_reason is what the real SDK hands back.
      empty_response = double("Response", content: [], stop_reason: "end_turn", usage: nil)
      allow(messages_double).to receive(:create).and_return(empty_response)
      expect {
        described_class.new.generate_bill_summary(prompt: prompt, model: model, schema: schema)
      }.to raise_error(Llm::TransportError, /unexpected response shape/)
    end

    it "raises Llm::TransportError naming the present block types when no block is text" do
      thinking_only_response = double(
        "Response", content: [make_thinking_block], stop_reason: "end_turn", usage: nil
      )
      allow(messages_double).to receive(:create).and_return(thinking_only_response)
      expect {
        described_class.new.generate_bill_summary(prompt: prompt, model: model, schema: schema)
      }.to raise_error(Llm::TransportError, /unexpected response shape.*"thinking"/m)
    end

    it "raises Llm::SchemaError on malformed JSON" do
      allow(messages_double).to receive(:create).and_return(make_response(text: "{not valid json"))
      expect {
        described_class.new.generate_bill_summary(prompt: prompt, model: model, schema: schema)
      }.to raise_error(Llm::SchemaError, /^Malformed JSON from claude/)
    end

    it "raises Llm::SchemaError when parsed Hash violates BILL_SUMMARY_SCHEMA" do
      allow(messages_double).to receive(:create).and_return(make_response(text: {"only_key" => "value"}.to_json))
      expect {
        described_class.new.generate_bill_summary(prompt: prompt, model: model, schema: schema)
      }.to raise_error(Llm::SchemaError, /^Schema validation failed/)
    end

    it "rescues APITimeoutError as Llm::TransportError 'claude transport: timeout (...)'" do
      allow(messages_double).to receive(:create)
        .and_raise(Anthropic::Errors::APITimeoutError.new(url: anthropic_url, message: "boom"))
      expect {
        described_class.new.generate_bill_summary(prompt: prompt, model: model, schema: schema)
      }.to raise_error(Llm::TransportError, /^claude transport: timeout/)
    end

    it "rescues APIConnectionError as Llm::TransportError 'claude transport: connection (...)'" do
      allow(messages_double).to receive(:create)
        .and_raise(Anthropic::Errors::APIConnectionError.new(url: anthropic_url, message: "boom"))
      expect {
        described_class.new.generate_bill_summary(prompt: prompt, model: model, schema: schema)
      }.to raise_error(Llm::TransportError, /^claude transport: connection/)
    end

    it "rescues RateLimitError as Llm::TransportError 'claude transport: 429 rate_limit'" do
      err = Anthropic::Errors::RateLimitError.new(
        url: anthropic_url,
        status: 429,
        headers: {}, #: Hash[String, untyped]
        body: nil,
        request: nil,
        response: nil,
        message: "rate-limited"
      )
      allow(messages_double).to receive(:create).and_raise(err)
      expect {
        described_class.new.generate_bill_summary(prompt: prompt, model: model, schema: schema)
      }.to raise_error(Llm::TransportError, /^claude transport: 429 rate_limit/)
    end

    it "rescues AuthenticationError as Llm::TransportError 'claude transport: 401 authentication'" do
      err = Anthropic::Errors::AuthenticationError.new(
        url: anthropic_url,
        status: 401,
        headers: {}, #: Hash[String, untyped]
        body: nil,
        request: nil,
        response: nil,
        message: "unauthorized"
      )
      allow(messages_double).to receive(:create).and_raise(err)
      expect {
        described_class.new.generate_bill_summary(prompt: prompt, model: model, schema: schema)
      }.to raise_error(Llm::TransportError, /^claude transport: 401 authentication/)
    end

    it "rescues APIStatusError (generic) with the status + class-demodulized name" do
      err = Anthropic::Errors::APIStatusError.new(
        url: anthropic_url,
        status: 500,
        headers: {}, #: Hash[String, untyped]
        body: nil,
        request: nil,
        response: nil,
        message: "server error"
      )
      allow(messages_double).to receive(:create).and_raise(err)
      expect {
        described_class.new.generate_bill_summary(prompt: prompt, model: model, schema: schema)
      }.to raise_error(Llm::TransportError, /^claude transport: 500 api_status_error/)
    end
  end

  describe "instrumentation (#last_usage, #last_response)" do
    it "exposes last_response after a successful call" do
      response = make_response(text: valid_payload_json)
      allow(messages_double).to receive(:create).and_return(response)
      adapter = described_class.new
      adapter.generate_bill_summary(prompt: prompt, model: model, schema: schema)
      expect(adapter.last_response).to eq(response)
    end

    it "exposes last_usage after a successful call" do
      response = make_response(text: valid_payload_json)
      allow(messages_double).to receive(:create).and_return(response)
      adapter = described_class.new
      adapter.generate_bill_summary(prompt: prompt, model: model, schema: schema)
      expect(adapter.last_usage).to eq(response.usage)
    end
  end

  describe "usage recording on the Anthropic direct path" do
    let(:allowed_domains) { ["thebanner.com"] }

    it "records usage on structured call (point 3: generate_structured)" do
      usage = double("Usage", input_tokens: 1200, output_tokens: 350, cache_creation_input_tokens: 500, cache_read_input_tokens: 200)
      response = double("Response", content: [make_thinking_block, double("ContentBlock", type: "text", text: valid_payload_json)], stop_reason: "end_turn", usage: usage, model: "claude-sonnet-5-5")
      allow(messages_double).to receive(:create).and_return(response)

      expect(SwayLogging).to receive(:info).with(
        "claude.usage.recorded",
        model: "claude-sonnet-5-5",
        input_tokens: 1200,
        output_tokens: 350,
        cache_creation_input_tokens: 500,
        cache_read_input_tokens: 200
      )

      described_class.new.generate_bill_summary(prompt: prompt, model: model, schema: schema)
    end

    it "formats integers so shell pipeline can sum input and output tokens" do
      usage = double("Usage", input_tokens: 1500, output_tokens: 300)
      response = double("Response", content: [make_thinking_block, double("ContentBlock", type: "text", text: valid_payload_json)], stop_reason: "end_turn", usage: usage, model: "claude-sonnet-5-5")
      allow(messages_double).to receive(:create).and_return(response)

      log_output = nil
      allow(Rails.logger).to receive(:info) do |msg|
        log_output = msg if msg.to_s.include?("claude.usage.recorded")
      end

      described_class.new.generate_bill_summary(prompt: prompt, model: model, schema: schema)

      expect(log_output).to include("claude.usage.recorded")
      expect(log_output).to include("input_tokens=1500")
      expect(log_output).to include("output_tokens=300")
      expect(log_output).not_to include("[FILTERED]")
    end
  end

  describe "client memoization" do
    it "constructs Anthropic::Client once per adapter instance and reuses it" do
      expect(Anthropic::Client).to receive(:new).once.and_return(client_double)
      allow(messages_double).to receive(:create).and_return(make_response(text: valid_payload_json))
      adapter = described_class.new
      adapter.generate_bill_summary(prompt: prompt, model: model, schema: schema)
      adapter.generate_bill_summary(prompt: prompt, model: model, schema: schema)
    end

    # The API key is looked up late, inside #generate_structured, which
    # promises only Llm::TransportError or SchemaError. A bare KeyError
    # broke that promise, catching out a fail-open rescue.
    it "translates a missing ANTHROPIC_API_KEY into Llm::TransportError" do
      original_key = ENV["ANTHROPIC_API_KEY"]
      begin
        ENV.delete("ANTHROPIC_API_KEY")

        expect {
          described_class.new.generate_bill_summary(prompt: prompt, model: model, schema: schema)
        }.to raise_error(Llm::TransportError, /ANTHROPIC_API_KEY/)
      ensure
        ENV["ANTHROPIC_API_KEY"] = original_key
      end
    end

    # Llm::Client hit this first: an empty-string env var (an easy kamal env
    # push slip) is what ENV.fetch returns instead of falling back to a
    # default. Fail the same way as a missing key.
    it "treats a blank ANTHROPIC_API_KEY the same as a missing one" do
      original_key = ENV["ANTHROPIC_API_KEY"]
      begin
        ENV["ANTHROPIC_API_KEY"] = "   "

        expect {
          described_class.new.generate_bill_summary(prompt: prompt, model: model, schema: schema)
        }.to raise_error(Llm::TransportError, /ANTHROPIC_API_KEY/)
      ensure
        ENV["ANTHROPIC_API_KEY"] = original_key
      end
    end

    # A key with a trailing newline (from kamal env push or cat) passes the
    # blank check but goes out in the header. Tested live: Anthropic
    # answers 401, indistinguishable from a real bad key.
    it "strips the key before handing it to the SDK, so a stray newline is not reported as a bad key" do
      captured = nil #: Hash[Symbol, untyped]?
      allow(Anthropic::Client).to receive(:new) do |**kwargs|
        captured = kwargs
        client_double
      end
      allow(messages_double).to receive(:create).and_return(make_response(text: valid_payload_json))
      original_key = ENV["ANTHROPIC_API_KEY"]
      begin
        ENV["ANTHROPIC_API_KEY"] = "sk-ant-api03-realkeymaterial\n"

        described_class.new.generate_bill_summary(prompt: prompt, model: model, schema: schema)

        expect(captured).to be_a(Hash)
        expect(captured&.fetch(:api_key, nil)).to eq("sk-ant-api03-realkeymaterial")
      ensure
        ENV["ANTHROPIC_API_KEY"] = original_key
      end
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
      allow(messages_double).to receive(:create).and_return(make_response(text: valid_categories_json))
      result = described_class.new.generate_bill_categories(
        prompt: prompt, model: model, schema: categories_schema
      )
      expect(result).to be_a(Hash)
      expect(result["categories"]).to eq(["Health", "Environment"])
    end

    # This used to expect a 4-item array to RAISE; it no longer does, and
    # that's right. StructuredOutputSchema strips maxItems SENT while our
    # validator still enforces it, so trimming beats discarding.
    it "degrades a 4-item array to the schema's maxItems instead of discarding the response" do
      allow(messages_double).to receive(:create).and_return(make_response(text: four_item_categories_json))

      result = described_class.new.generate_bill_categories(
        prompt: prompt, model: model, schema: categories_schema
      )

      expect(result["categories"].length).to eq(3)
    end

    # validation_schema is fixed at boot so a caller can't loosen
    # validation, but schema_hash used to come from the caller's argument —
    # handing over the one control the adapter refuses.
    it "normalizes against the boot schema, not against a caller-supplied hash" do
      hostile = BILL_CATEGORIES_SCHEMA_HASH.deep_dup
      hostile["properties"]["categories"]["maxItems"] = 1
      allow(messages_double).to receive(:create).and_return(make_response(text: valid_categories_json))

      result = described_class.new.generate_bill_categories(
        prompt: prompt, model: model, schema: hostile
      )

      expect(result["categories"]).to eq(["Health", "Environment"])
    end

    it "raises Llm::SchemaError for an empty array response (minItems:1 violated)" do
      allow(messages_double).to receive(:create).and_return(make_response(text: empty_categories_json))
      expect {
        described_class.new.generate_bill_categories(
          prompt: prompt, model: model, schema: categories_schema
        )
      }.to raise_error(Llm::SchemaError)
    end

    it "raises Llm::TransportError on Anthropic::Errors::APITimeoutError" do
      anthropic_url = URI("https://api.anthropic.com/v1/messages")
      allow(messages_double).to receive(:create)
        .and_raise(Anthropic::Errors::APITimeoutError.new(url: anthropic_url, message: "timeout"))
      expect {
        described_class.new.generate_bill_categories(
          prompt: prompt, model: model, schema: categories_schema
        )
      }.to raise_error(Llm::TransportError, /^claude transport: timeout/)
    end

    it "raises Llm::TransportError on Anthropic::Errors::APIConnectionError" do
      anthropic_url = URI("https://api.anthropic.com/v1/messages")
      allow(messages_double).to receive(:create)
        .and_raise(Anthropic::Errors::APIConnectionError.new(url: anthropic_url, message: "connection refused"))
      expect {
        described_class.new.generate_bill_categories(
          prompt: prompt, model: model, schema: categories_schema
        )
      }.to raise_error(Llm::TransportError, /^claude transport: connection/)
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

    # This used to be an ambiguous payload breaking BOTH schemas, proving
    # nothing about which was wired. This one passes SUMMARY and fails
    # POSITIONS, failing only if positions validates.
    def summary_shaped_positions_json
      {
        "summary_markdown" => "A valid summary body.",
        "full_breakdown_markdown" => "A valid breakdown body."
      }.to_json
    end

    it "happy path: returns the parsed, schema-validated Hash" do
      allow(messages_double).to receive(:create).and_return(make_response(text: valid_positions_json))
      result = described_class.new.generate_bill_positions(
        prompt: prompt, model: model, schema: positions_schema
      )
      expect(result).to be_a(Hash)
      expect(BILL_POSITIONS_SCHEMA.validate(result).to_a).to be_empty
    end

    it "raises Llm::SchemaError for a payload that BILL_SUMMARY_SCHEMA would accept (proves BILL_POSITIONS_SCHEMA is wired)" do
      allow(messages_double).to receive(:create).and_return(make_response(text: summary_shaped_positions_json))
      expect {
        described_class.new.generate_bill_positions(
          prompt: prompt, model: model, schema: positions_schema
        )
      }.to raise_error(Llm::SchemaError)
    end

    it "raises Llm::TransportError on Anthropic::Errors::APITimeoutError" do
      anthropic_url = URI("https://api.anthropic.com/v1/messages")
      allow(messages_double).to receive(:create)
        .and_raise(Anthropic::Errors::APITimeoutError.new(url: anthropic_url, message: "timeout"))
      expect {
        described_class.new.generate_bill_positions(
          prompt: prompt, model: model, schema: positions_schema
        )
      }.to raise_error(Llm::TransportError, /^claude transport: timeout/)
    end
  end

  # Of the four public generate_* methods, this had no adapter-level
  # tests — 50 references only proved it EXISTS. It mirrors
  # generate_bill_positions, so a copy-paste slip fails open here.
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

    # This payload passes BILL_POSITIONS_SCHEMA (empty array allowed) and
    # fails TESTIMONY_CLASSIFICATION_SCHEMA (missing/extra keys), failing
    # only if classification validates — the slip this invites.
    def positions_shaped_classification_json
      {"draft_org_positions" => []}.to_json
    end

    it "happy path: returns the parsed, schema-validated Hash" do
      allow(messages_double).to receive(:create).and_return(make_response(text: valid_classification_json))
      result = described_class.new.generate_testimony_classification(
        prompt: prompt, model: model, schema: classification_schema
      )
      expect(result).to be_a(Hash)
      expect(TESTIMONY_CLASSIFICATION_SCHEMA.validate(result).to_a).to be_empty
    end

    it "raises Llm::SchemaError for a payload that BILL_POSITIONS_SCHEMA would accept (proves TESTIMONY_CLASSIFICATION_SCHEMA is wired)" do
      allow(messages_double).to receive(:create)
        .and_return(make_response(text: positions_shaped_classification_json))
      expect {
        described_class.new.generate_testimony_classification(
          prompt: prompt, model: model, schema: classification_schema
        )
      }.to raise_error(Llm::SchemaError)
    end

    it "raises Llm::TransportError on Anthropic::Errors::APITimeoutError" do
      anthropic_url = URI("https://api.anthropic.com/v1/messages")
      allow(messages_double).to receive(:create)
        .and_raise(Anthropic::Errors::APITimeoutError.new(url: anthropic_url, message: "timeout"))
      expect {
        described_class.new.generate_testimony_classification(
          prompt: prompt, model: model, schema: classification_schema
        )
      }.to raise_error(Llm::TransportError, /^claude transport: timeout/)
    end
  end

  describe "#generate_news_claim_grounding" do
    let(:grounding_schema) { NEWS_CLAIM_GROUNDING_SCHEMA_HASH }

    def valid_grounding_json
      {"verdict" => "supported", "reason" => "Grounding corroborated."}.to_json
    end

    it "happy path: returns the parsed, schema-validated Hash" do
      allow(messages_double).to receive(:create).and_return(make_response(text: valid_grounding_json))
      result = described_class.new.generate_news_claim_grounding(
        prompt: prompt, model: model, schema: grounding_schema
      )
      expect(result).to eq({"verdict" => "supported", "reason" => "Grounding corroborated."})
    end

    it "raises Llm::SchemaError for invalid schema payload" do
      allow(messages_double).to receive(:create).and_return(make_response(text: {"invalid" => "payload"}.to_json))
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
          {"position" => 0, "stance" => "oppose"}
        ]
      }.to_json

      allow(messages_double).to receive(:create).and_return(make_response(text: valid_stance_json))
      result = described_class.new.generate_testimony_stance_classification(
        prompt: prompt, model: model, schema: stance_schema
      )
      expect(result["classifications"].first["stance"]).to eq("oppose")
    end

    it "raises Llm::SchemaError for invalid schema payload" do
      stance_schema = TESTIMONY_STANCE_CLASSIFICATION_SCHEMA_HASH
      allow(messages_double).to receive(:create).and_return(make_response(text: {"invalid" => "payload"}.to_json))
      expect {
        described_class.new.generate_testimony_stance_classification(
          prompt: prompt, model: model, schema: stance_schema
        )
      }.to raise_error(Llm::SchemaError)
    end
  end
end
