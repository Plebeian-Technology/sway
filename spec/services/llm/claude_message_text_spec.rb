# frozen_string_literal: true

require "rails_helper"

# The three checks every Claude reply must survive before its text is parsed,
# in the order they must run. Shared by the synchronous adapter and the batch
# service; the adapter lets these raise, the batch service catches them per
# item, but the checks and their wording are the same on both paths.
RSpec.describe Llm::ClaudeMessageText do
  def text_block(text)
    double("ContentBlock", type: "text", text: text)
  end

  def tool_use_block
    double("ToolUseBlock", type: "tool_use")
  end

  def claude_message(content:, stop_reason: "end_turn")
    double("Message", content: content, stop_reason: stop_reason)
  end

  describe ".extract" do
    it "returns the text of the first text block" do
      expect(described_class.extract(claude_message(content: [text_block("{\"a\":1}")]))).to eq("{\"a\":1}")
    end

    it "skips a leading non-text block rather than reading position zero" do
      expect(described_class.extract(claude_message(content: [tool_use_block, text_block("payload")]))).to eq("payload")
    end

    it "raises Llm::SchemaError when the reply was truncated at max_tokens" do
      expect {
        described_class.extract(claude_message(content: [text_block("half a jso")], stop_reason: "max_tokens"))
      }.to raise_error(Llm::SchemaError, /^claude schema: response truncated \(stop_reason=max_tokens\)/)
    end

    it "checks truncation before the text block, so a truncated reply is never parsed" do
      expect {
        described_class.extract(claude_message(content: [text_block("")], stop_reason: "max_tokens"))
      }.to raise_error(Llm::SchemaError, /truncated/)
    end

    it "raises Llm::TransportError naming the block types when no text block is present" do
      expect {
        described_class.extract(claude_message(content: [tool_use_block]))
      }.to raise_error(Llm::TransportError, /unexpected response shape/) { |e|
        expect(e.message).to include("tool_use")
      }
    end

    it "raises Llm::TransportError on an empty content array" do
      expect {
        described_class.extract(claude_message(content: []))
      }.to raise_error(Llm::TransportError, /unexpected response shape/)
    end

    it "raises Llm::TransportError on whitespace-only text" do
      expect {
        described_class.extract(claude_message(content: [text_block("   \n  ")]))
      }.to raise_error(Llm::TransportError, /^claude transport: empty response/)
    end

    it "accepts a symbol stop_reason, as some SDK shapes return" do
      expect {
        described_class.extract(claude_message(content: [text_block("x")], stop_reason: :max_tokens))
      }.to raise_error(Llm::SchemaError, /truncated/)
    end

    it "accepts a symbol block type, as some SDK shapes return" do
      symbol_block = double("ContentBlock", type: :text, text: "payload")
      expect(described_class.extract(claude_message(content: [symbol_block]))).to eq("payload")
    end
  end
end
