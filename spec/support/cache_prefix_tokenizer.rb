# frozen_string_literal: true

# @lat: [[cache-prefix-tokenizer-design#What count's returned token count includes]]
module CachePrefixTokenizer
  # @lat: [[llm-prompt-cache-silent-failure#The token-estimation ratio drifted twice]]
  TIER_2_CHARS_PER_TOKEN = Llm::PromptCache::CHARS_PER_TOKEN

  module_function

  # @param system_prompt [String] the prefix text that can be cached
  # @param model [String] the Claude model id to count tokens for
  # @return [Integer, nil] input_tokens count, or nil if Tier 1 unavailable.
  #
  # @lat: [[cache-prefix-tokenizer-design#What count's returned token count includes]]
  def count(system_prompt, model: "claude-haiku-5-5")
    begin
      require "anthropic"
    rescue LoadError
      return nil
    end
    # @lat: [[cache-prefix-tokenizer-design#Why the live-calls opt-in is checked before the API key]]
    return nil unless LiveLlmGate.enabled?

    api_key = ENV["ANTHROPIC_API_KEY"].to_s.strip
    return nil if api_key.empty?

    # @lat: [[cache-prefix-tokenizer-design#Why every Anthropic::Errors::Error becomes nil, not a raised failure]]
    begin
      client = Anthropic::Client.new(api_key: api_key, timeout: LiveLlmGate::TIMEOUT_SECONDS.to_f)
      response = client.messages.count_tokens(
        model: model,
        system_: [
          Anthropic::TextBlockParam.new(text: system_prompt, cache_control: Anthropic::CacheControlEphemeral.new)
        ],
        messages: [Anthropic::MessageParam.new(role: :user, content: ".")]
      )
      response.input_tokens
    rescue Anthropic::Errors::Error => e
      Rails.logger.warn("CachePrefixTokenizer Tier 1 failed (#{e.class}); falling back to Tier 2 heuristic")
      nil
    end
  end
end
