# frozen_string_literal: true

module Llm
  # @lat: [[lat.md/explanation/llm-summaries#Talking to the Anthropic SDK]]
  module ClaudeMessageText
    def self.extract(message)
      if message.stop_reason.to_s == "max_tokens"
        raise Llm::SchemaError,
          "claude schema: response truncated (stop_reason=max_tokens) — extend MAX_TOKENS or trim source"
      end

      text_block = message.content.find { |block| block.type.to_s == "text" }
      if text_block.nil?
        block_types = message.content.map(&:type)
        raise Llm::TransportError,
          "claude transport: unexpected response shape (no text block among block types=#{block_types.inspect}, stop_reason=#{message.stop_reason.inspect}) — a preceding thinking block is one cause, structured outputs routing the JSON into a tool_use block instead of text is another; verify the output_config.format request shape"
      end

      text = text_block.text.to_s
      raise Llm::TransportError, "claude transport: empty response" if text.strip.empty?

      text
    end
  end
end
