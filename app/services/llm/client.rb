# frozen_string_literal: true

module Llm
  # @lat: [[llm-summaries#Two adapters, one client]]
  module Client
    module_function

    def build(provider: nil)
      effective = provider.to_s.strip
      effective = Sway::Settings.llm.llm_provider if effective.empty?

      case effective
      when "claude"
        Llm::ClaudeAdapter.new
      when "llamacpp"
        Llm::LlamacppAdapter.new
      when "openrouter"
        Llm::OpenRouterAdapter.new
      else
        raise ArgumentError, "unknown provider: #{effective.inspect} (allowed: claude, llamacpp, openrouter)"
      end
    end

    # @lat: [[news-article-evidence#Grounding decisions]]
    def generate_news_claim_grounding(prompt:, model:, schema:, provider: nil)
      build(provider: provider).generate_news_claim_grounding(prompt: prompt, model: model, schema: schema)
    end

    # @lat: [[llm-summaries#What a third provider reached through OpenRouter exposes#OpenRouter Decisions API transport for System One models]]
    def generate_decisions(model:, state:, questions:, provider: "openrouter")
      adapter = build(provider: provider)
      unless adapter.respond_to?(:generate_decisions)
        raise ArgumentError, "Provider #{provider.inspect} does not support generate_decisions"
      end

      adapter.generate_decisions(model: model, state: state, questions: questions)
    end

    # @lat: [[llm-summaries#What a third provider reached through OpenRouter exposes#ScaleDown entity extraction through constrained decoding]]
    def generate_entity_extraction(model:, content:, entities:, max_tokens: nil, provider: "openrouter")
      adapter = build(provider: provider)
      unless adapter.respond_to?(:generate_entity_extraction)
        raise ArgumentError, "Provider #{provider.inspect} does not support generate_entity_extraction"
      end

      adapter.generate_entity_extraction(
        model: model,
        content: content,
        entities: entities,
        max_tokens: max_tokens
      )
    end
  end
end
