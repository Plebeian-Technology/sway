# frozen_string_literal: true

require "rails_helper"

RSpec.describe Llm::ClaudeRequestParams do
  let(:prompt) do
    Llm::PromptPayload.new(
      system_prompt: "STABLE SYSTEM PROMPT",
      user_message: "PER-BILL USER MESSAGE"
    )
  end
  let(:model) { "claude-haiku-5-5" }
  let(:schema) { BILL_SUMMARY_SCHEMA_HASH }

  describe ".build" do
    it "returns exactly model, max_tokens, system, messages, output_config" do
      result = described_class.build(prompt: prompt, model: model, schema: schema)
      expect(result.keys).to contain_exactly(:model, :max_tokens, :system, :messages, :output_config)
    end

    it "carries the model through unchanged" do
      result = described_class.build(prompt: prompt, model: "claude-sonnet-5-5", schema: schema)
      expect(result[:model]).to eq("claude-sonnet-5-5")
    end

    it "sets max_tokens to MAX_TOKENS (4096)" do
      result = described_class.build(prompt: prompt, model: model, schema: schema)
      expect(described_class::MAX_TOKENS).to eq(4096)
      expect(result[:max_tokens]).to eq(described_class::MAX_TOKENS)
    end

    it "builds messages as a single user turn" do
      result = described_class.build(prompt: prompt, model: model, schema: schema)
      expect(result[:messages]).to eq([{role: "user", content: "PER-BILL USER MESSAGE"}])
    end

    it "attaches cache_control when the prefix clears the model floor" do
      long_prompt = Llm::PromptPayload.new(system_prompt: "S" * 7366, user_message: "x")
      result = described_class.build(prompt: long_prompt, model: "claude-sonnet-5-5", schema: schema)
      block = result[:system].first
      expect(block[:type]).to eq("text")
      expect(block[:text]).to eq("S" * 7366)
      expect(block[:cache_control]).to eq({type: "ephemeral"})
    end

    it "omits cache_control when the prefix cannot clear the model floor" do
      result = described_class.build(prompt: prompt, model: model, schema: schema)
      block = result[:system].first
      expect(block[:text]).to eq("STABLE SYSTEM PROMPT")
      expect(block).not_to have_key(:cache_control)
    end

    it "sends output_config.format with type json_schema and the request-safe schema" do
      result = described_class.build(prompt: prompt, model: model, schema: schema)
      fmt = result.dig(:output_config, :format)
      expect(fmt[:type]).to eq("json_schema")
      expect(fmt[:schema]).to eq(Llm::StructuredOutputSchema.for_request(schema))
      expect(fmt[:schema]).not_to eq(schema)
    end

    it "is the exact hash ClaudeAdapter feeds into messages.create, minus request_options" do
      result = described_class.build(prompt: prompt, model: model, schema: schema)
      expect(result).to eq(
        model: model,
        max_tokens: 4096,
        system: [{type: "text", text: "STABLE SYSTEM PROMPT"}],
        messages: [{role: "user", content: "PER-BILL USER MESSAGE"}],
        output_config: {format: {type: "json_schema", schema: Llm::StructuredOutputSchema.for_request(schema)}}
      )
    end
  end
end
