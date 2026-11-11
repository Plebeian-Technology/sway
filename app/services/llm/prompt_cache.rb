# frozen_string_literal: true

module Llm
  # @lat: [[llm-prompt-cache-silent-failure#The silent failure this module exists to close]]
  module PromptCache
    # @lat: [[llm-prompt-cache-thresholds#Near-miss log band]]
    # @lat: [[llm-prompt-cache-silent-failure#The silent failure this module exists to close]]
    MINIMUM_CACHEABLE_PREFIX_TOKENS = {
      "claude-haiku-4-5" => 4096,
      "claude-haiku-5-5" => 4096,
      "claude-sonnet-4-5" => 1024,
      "claude-sonnet-4-6" => 1024,
      "claude-sonnet-5" => 1024,
      "claude-sonnet-5-5" => 1024,
      "claude-opus-4-8" => 1024,
      "claude-opus-5-5" => 512
    }.freeze

    # @lat: [[llm-prompt-cache-silent-failure#The silent failure this module exists to close]]
    CHARS_PER_TOKEN = 3.5

    EPHEMERAL = {type: "ephemeral"}.freeze

    # @lat: [[llm-prompt-cache-silent-failure#The silent failure this module exists to close]]
    NEAR_MISS_LOG_RATIO = 0.75

    # @lat: [[llm-prompt-cache-silent-failure#The silent failure this module exists to close]]
    def self.minimum_prefix_tokens(model)
      match = MINIMUM_CACHEABLE_PREFIX_TOKENS
        .select { |family, _| model.to_s.start_with?(family) }
        .max_by { |family, _| family.length }
      match&.last
    end

    def self.estimated_tokens(text)
      (text.to_s.length / CHARS_PER_TOKEN).floor
    end

    # @lat: [[llm-summaries#Two adapters, one client]]
    def self.cacheable?(system_prompt, model:)
      minimum = minimum_prefix_tokens(model)
      if minimum.nil?
        SwayLogging.warn("llm.prompt_cache.unknown_model", model: model.to_s)
        return false
      end

      estimated_tokens(system_prompt) >= minimum
    end

    # @lat: [[llm-prompt-cache-silent-failure#The silent failure this module exists to close]]
    def self.cache_control_for(system_prompt, model:)
      return EPHEMERAL if cacheable?(system_prompt, model: model)

      minimum = minimum_prefix_tokens(model)
      estimated = estimated_tokens(system_prompt)

      # @lat: [[llm-prompt-cache-silent-failure#The silent failure this module exists to close]]
      if minimum && estimated >= minimum * NEAR_MISS_LOG_RATIO
        SwayLogging.warn(
          "llm.prompt_cache.withheld",
          model: model,
          prefix_chars: system_prompt.to_s.length,
          estimated_tokens: estimated,
          minimum_prefix_tokens: minimum,
          near_miss_log_ratio: NEAR_MISS_LOG_RATIO,
          chars_per_token: CHARS_PER_TOKEN
        )
      end
      nil
    end
  end
end
