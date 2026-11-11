# frozen_string_literal: true

module Llm
  class UnknownRouteError < ArgumentError; end unless const_defined?(:UnknownRouteError)

  module ModelCatalog
    UnknownRouteError = Llm::UnknownRouteError

    # @lat: [[llm-summaries#What a third provider reached through OpenRouter exposes]]
    class ModelRoute < Struct.new(:provider, :api_model, :label, :supports_reasoning, :mode)
      def mode
        self[:mode] || :chat
      end

      def decision_model?
        mode == :decision
      end

      def extraction_model?
        mode == :extraction
      end

      def openrouter?
        provider == :openrouter
      end

      def claude?
        provider == :claude
      end

      def llamacpp?
        provider == :llamacpp
      end

      def supports_reasoning?
        if decision_model? || extraction_model?
          supports_reasoning == true
        else
          supports_reasoning.nil? ? openrouter? : (supports_reasoning == true)
        end
      end

      def to_ary
        [provider, api_model]
      end

      def deconstruct
        [provider, api_model]
      end

      def deconstruct_keys(keys)
        h = {
          provider: provider,
          api_model: api_model,
          label: label,
          supports_reasoning: supports_reasoning?,
          mode: mode
        }
        keys ? h.slice(*keys) : h
      end
    end

    OPUS_LATEST_ROUTE = ModelRoute.new(
      provider: :openrouter,
      api_model: "~anthropic/claude-opus-latest",
      label: "Opus Latest"
    ).freeze

    SONNET_LATEST_ROUTE = ModelRoute.new(
      provider: :openrouter,
      api_model: "~anthropic/claude-sonnet-latest",
      label: "Sonnet Latest"
    ).freeze

    HAIKU_LATEST_ROUTE = ModelRoute.new(
      provider: :openrouter,
      api_model: "~anthropic/claude-haiku-latest",
      label: "Haiku Latest"
    ).freeze

    GEMINI_ARGON_LATEST_ROUTE = ModelRoute.new(
      provider: :openrouter,
      api_model: "google/gemini-4-argon",
      label: "Gemini Argon Latest"
    ).freeze

    GEMINI_FLASH_LATEST_ROUTE = ModelRoute.new(
      provider: :openrouter,
      api_model: "~google/gemini-flash-latest",
      label: "Gemini Flash Latest"
    ).freeze

    GLM_LATEST_ROUTE = ModelRoute.new(
      provider: :openrouter,
      api_model: "~z-ai/glm-latest",
      label: "GLM Latest"
    ).freeze

    DEEPSEEK_PRO_ROUTE = ModelRoute.new(
      provider: :openrouter,
      api_model: "~deepseek/deepseek-pro-latest",
      label: "Deepseek Pro Latest"
    ).freeze

    DEEPSEEK_FLASH_ROUTE = ModelRoute.new(
      provider: :openrouter,
      api_model: "~deepseek/deepseek-flash-latest",
      label: "Deepseek Flash Latest"
    ).freeze

    OPENROUTER_AUTO_ROUTE = ModelRoute.new(
      provider: :openrouter,
      api_model: "openrouter/auto",
      label: "OpenRouter Auto"
    ).freeze

    SCALEDOWN_CLASSIFY_LATEST_ROUTE = ModelRoute.new(
      provider: :openrouter,
      api_model: "scaledown/classify-1",
      label: "ScaleDown Classify Latest",
      supports_reasoning: false,
      mode: :decision
    ).freeze

    JEV_LATEST_ROUTE = ModelRoute.new(
      provider: :openrouter,
      api_model: "~typesafe/jev-latest",
      label: "Jev Latest",
      supports_reasoning: false,
      mode: :decision
    ).freeze

    PERPLEXITY_DECIDER_LATEST_ROUTE = ModelRoute.new(
      provider: :openrouter,
      api_model: "~perplexity/pplx-decider-latest",
      label: "Perplexity Decider Latest",
      supports_reasoning: false,
      mode: :decision
    ).freeze

    PERPLEXITY_DECIDER_FLASH_LATEST_ROUTE = ModelRoute.new(
      provider: :openrouter,
      api_model: "~perplexity/pplx-decider-flash-latest",
      label: "Perplexity Decider Flash Latest",
      supports_reasoning: false,
      mode: :decision
    ).freeze

    SCALEDOWN_EXTRACT_LATEST_ROUTE = ModelRoute.new(
      provider: :openrouter,
      api_model: "scaledown/extract",
      label: "ScaleDown Extract Latest",
      supports_reasoning: false,
      mode: :extraction
    ).freeze

    OPENROUTER_ROUTES = {
      "Opus Latest" => OPUS_LATEST_ROUTE,
      "~anthropic/claude-opus-latest" => OPUS_LATEST_ROUTE,
      "Sonnet Latest" => SONNET_LATEST_ROUTE,
      "~anthropic/claude-sonnet-latest" => SONNET_LATEST_ROUTE,
      "Haiku Latest" => HAIKU_LATEST_ROUTE,
      "~anthropic/claude-haiku-latest" => HAIKU_LATEST_ROUTE,
      "Gemini Argon Latest" => GEMINI_ARGON_LATEST_ROUTE,
      "google/gemini-4-argon" => GEMINI_ARGON_LATEST_ROUTE,
      "Gemini Flash Latest" => GEMINI_FLASH_LATEST_ROUTE,
      "~google/gemini-flash-latest" => GEMINI_FLASH_LATEST_ROUTE,
      "GLM Latest" => GLM_LATEST_ROUTE,
      "~z-ai/glm-latest" => GLM_LATEST_ROUTE,
      "Deepseek Pro Latest" => DEEPSEEK_PRO_ROUTE,
      "~deepseek/deepseek-pro-latest" => DEEPSEEK_PRO_ROUTE,
      "deepseek/deepseek-pro-latest" => DEEPSEEK_PRO_ROUTE,
      "deepseek-pro-latest" => DEEPSEEK_PRO_ROUTE,
      "Deepseek Flash Latest" => DEEPSEEK_FLASH_ROUTE,
      "~deepseek/deepseek-flash-latest" => DEEPSEEK_FLASH_ROUTE,
      "deepseek/deepseek-flash-latest" => DEEPSEEK_FLASH_ROUTE,
      "deepseek-flash-latest" => DEEPSEEK_FLASH_ROUTE,
      "deepseek/deepseek-flash" => DEEPSEEK_FLASH_ROUTE,
      "OpenRouter Auto" => OPENROUTER_AUTO_ROUTE,
      "openrouter/auto" => OPENROUTER_AUTO_ROUTE,
      "openrouter-auto" => OPENROUTER_AUTO_ROUTE
    }.freeze

    OPENROUTER_DECISION_ROUTES = {
      "ScaleDown Classify Latest" => SCALEDOWN_CLASSIFY_LATEST_ROUTE,
      "scaledown/classify-1" => SCALEDOWN_CLASSIFY_LATEST_ROUTE,
      "Jev Latest" => JEV_LATEST_ROUTE,
      "~typesafe/jev-latest" => JEV_LATEST_ROUTE,
      "typesafe/jev-1.14" => JEV_LATEST_ROUTE,
      "typesafe/jev-latest" => JEV_LATEST_ROUTE,
      "Perplexity Decider Latest" => PERPLEXITY_DECIDER_LATEST_ROUTE,
      "~perplexity/pplx-decider-latest" => PERPLEXITY_DECIDER_LATEST_ROUTE,
      "Perplexity Decider Flash Latest" => PERPLEXITY_DECIDER_FLASH_LATEST_ROUTE,
      "~perplexity/pplx-decider-flash-latest" => PERPLEXITY_DECIDER_FLASH_LATEST_ROUTE
    }.freeze

    OPENROUTER_EXTRACTION_ROUTES = {
      "ScaleDown Extract Latest" => SCALEDOWN_EXTRACT_LATEST_ROUTE,
      "scaledown/extract" => SCALEDOWN_EXTRACT_LATEST_ROUTE
    }.freeze

    ACTIVE_CLAUDE_ROUTES = {
      "claude-haiku-5-5" => ModelRoute.new(
        provider: :claude,
        api_model: "claude-haiku-5-5", # gitleaks:allow
        label: "Haiku 5.5"
      ).freeze,
      "claude-sonnet-5-5" => ModelRoute.new(
        provider: :claude,
        api_model: "claude-sonnet-5-5",
        label: "Sonnet 5.5"
      ).freeze,
      "claude-opus-5-5" => ModelRoute.new(
        provider: :claude,
        api_model: "claude-opus-5-5",
        label: "Opus 5.5"
      ).freeze
    }.freeze

    RETIRED_CLAUDE_ROUTES = {
      "claude-sonnet-4-6" => ModelRoute.new(
        provider: :claude,
        api_model: "claude-sonnet-4-6",
        label: "claude-sonnet-4-6"
      ).freeze,
      "claude-sonnet-4-5" => ModelRoute.new(
        provider: :claude,
        api_model: "claude-sonnet-4-5",
        label: "claude-sonnet-4-5"
      ).freeze,
      "claude-opus-4-8" => ModelRoute.new(
        provider: :claude,
        api_model: "claude-opus-4-8",
        label: "claude-opus-4-8"
      ).freeze
    }.freeze

    ALL_ROUTES = OPENROUTER_ROUTES
      .merge(OPENROUTER_DECISION_ROUTES)
      .merge(OPENROUTER_EXTRACTION_ROUTES)
      .merge(ACTIVE_CLAUDE_ROUTES)
      .merge(RETIRED_CLAUDE_ROUTES)
      .freeze

    module_function

    def lookup(choice, catalog_models: nil)
      return nil if choice.nil?

      key = choice.to_s.strip
      return nil if key.empty?

      if ALL_ROUTES.key?(key)
        return ALL_ROUTES.fetch(key)
      end

      entry = if catalog_models.nil?
        Llm::OpenRouterModelsService.lookup(key)
      else
        Llm::OpenRouterModelsService.lookup(key, models: catalog_models)
      end

      if entry.nil? && catalog_models.nil? && Llm::OpenRouterModelsService.respond_to?(:lookup_decision_model)
        entry = Llm::OpenRouterModelsService.lookup_decision_model(key)
      end

      if entry
        raw_mode = entry[:mode]
        entry_mode = raw_mode.is_a?(Symbol) ? raw_mode : :chat
        return ModelRoute.new(
          provider: :openrouter,
          api_model: entry.fetch(:id),
          label: entry.fetch(:label),
          supports_reasoning: entry.fetch(:supports_reasoning, true),
          mode: entry_mode
        )
      end

      if Llm::OpenRouterModelsService.valid_slug?(key) && AdminSetting.stored_model?(key)
        fallback_mode = begin
          if AdminSetting.column_names.include?("decision_model") && AdminSetting.exists?(decision_model: key)
            :decision
          elsif AdminSetting.column_names.include?("summarization_model") && AdminSetting.exists?(summarization_model: key)
            :chat
          elsif AdminSetting.column_names.include?("extraction_model") && AdminSetting.exists?(extraction_model: key)
            :extraction
          else
            :chat
          end
        rescue ActiveRecord::StatementInvalid, ActiveRecord::NoDatabaseError, ActiveRecord::ConnectionNotEstablished
          :chat
        end

        return ModelRoute.new(
          provider: :openrouter,
          api_model: key,
          label: key,
          supports_reasoning: (fallback_mode == :chat),
          mode: fallback_mode
        )
      end

      nil
    end

    def fetch(choice, catalog_models: nil)
      lookup(choice, catalog_models: catalog_models) || raise(UnknownRouteError, "unsupported or unknown model choice: #{choice.inspect}")
    end

    def supports_reasoning?(choice, catalog_models: nil)
      lookup(choice, catalog_models: catalog_models)&.supports_reasoning? == true
    end

    def decision_model?(choice, catalog_models: nil)
      lookup(choice, catalog_models: catalog_models)&.decision_model? == true
    end

    def extraction_model?(choice, catalog_models: nil)
      lookup(choice, catalog_models: catalog_models)&.extraction_model? == true
    end

    def openrouter_choices
      [
        "Opus Latest",
        "Sonnet Latest",
        "Haiku Latest",
        "Gemini Argon Latest",
        "Gemini Flash Latest",
        "GLM Latest",
        "Deepseek Pro Latest",
        "Deepseek Flash Latest",
        "OpenRouter Auto"
      ].freeze
    end

    def openrouter_decision_choices
      [
        "ScaleDown Classify Latest",
        "Jev Latest",
        "Perplexity Decider Latest",
        "Perplexity Decider Flash Latest"
      ].freeze
    end

    def openrouter_extraction_choices
      [
        "ScaleDown Extract Latest"
      ].freeze
    end

    def active_claude_choices
      ACTIVE_CLAUDE_ROUTES.keys.freeze
    end

    def retired_claude_choices
      RETIRED_CLAUDE_ROUTES.keys.freeze
    end

    def all_choices
      ALL_ROUTES.keys.freeze
    end
  end
end
