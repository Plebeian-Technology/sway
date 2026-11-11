# frozen_string_literal: true

module Llm
  class UnknownRouteError < ArgumentError; end unless const_defined?(:UnknownRouteError)

  module RouteResolver
    UnknownRouteError = Llm::UnknownRouteError

    # @lat: [[llm-summaries#What a third provider reached through OpenRouter exposes]]
    class Route < Struct.new(:provider, :api_model, :reasoning_effort, :mode)
      def mode
        self[:mode] || :chat
      end

      def decision_model?
        mode == :decision
      end

      def extraction_model?
        mode == :extraction
      end

      def to_ary
        [provider, api_model]
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

      def deconstruct
        [provider, api_model]
      end

      def deconstruct_keys(keys)
        h = {provider: provider, api_model: api_model, reasoning_effort: reasoning_effort, mode: mode}
        keys ? h.slice(*keys) : h
      end
    end

    module_function

    def resolve(
      model_choice: nil,
      purpose: :summary,
      per_run_override: nil,
      override: nil,
      fallback_model: nil,
      blank_fallback: nil,
      fallback: nil,
      active_models: nil,
      offered_models: nil,
      allowlist: nil,
      setting: nil,
      reasoning_effort: nil
    )
      normalized_purpose = case purpose.to_s.strip
      when "summary", "summarization"
        :summary
      when "classification"
        :classification
      when "decision", "decisions"
        :decision
      when "extraction", "extract"
        :extraction
      else
        raise ArgumentError, "unknown purpose: #{purpose.inspect} (must be :summary, :classification, :decision, or :extraction)"
      end

      effective_override = per_run_override || override
      effective_fallback = fallback_model || blank_fallback || fallback

      setting_record = nil
      fetch_setting = lambda do
        setting_record ||= setting || AdminSetting.singleton
      end

      base_candidate = if model_choice.present?
        model_choice.to_s.strip
      else
        setting_inst = fetch_setting.call
        stored = case normalized_purpose
        when :summary
          setting_inst.summarization_model
        when :classification
          setting_inst.classification_model
        when :decision
          setting_inst.decision_model if setting_inst.respond_to?(:decision_model)
        when :extraction
          setting_inst.extraction_model if setting_inst.respond_to?(:extraction_model)
        end
        default_fallback = case normalized_purpose
        when :decision
          AdminSetting::SUPPORTED_DECISION_MODELS.first
        when :extraction
          AdminSetting::SUPPORTED_EXTRACTION_MODELS.first
        end
        stored.presence || effective_fallback || default_fallback
      end

      override_accepted = false
      candidate = if normalized_purpose == :summary && effective_override.present?
        override_str = effective_override.to_s.strip
        allowed_models = active_models || offered_models || allowlist || (setting ? setting.offered_models_list : AdminSetting.offered_models)
        if allowed_models.include?(override_str)
          override_accepted = true
          override_str
        else
          base_candidate
        end
      else
        base_candidate
      end

      if candidate.blank?
        raise UnknownRouteError, "no model choice resolved for #{normalized_purpose}"
      end

      catalog_route = Llm::ModelCatalog.fetch(candidate)

      resolved_effort = if catalog_route.supports_reasoning?
        raw_effort = reasoning_effort.to_s.strip
        if normalized_purpose == :summary && effective_override.present? && !override_accepted
          raw_effort = ""
        end

        if raw_effort.casecmp("default").zero?
          nil
        elsif raw_effort.present? && AdminSetting::REASONING_EFFORTS.include?(raw_effort)
          raw_effort
        elsif !override_accepted || candidate == base_candidate
          case normalized_purpose
          when :summary
            fetch_setting.call.summarization_reasoning_effort.to_s.strip.presence
          when :classification
            fetch_setting.call.classification_reasoning_effort.to_s.strip.presence
          end
        end
      end

      case catalog_route.provider
      when :openrouter
        Route.new(provider: :openrouter, api_model: catalog_route.api_model, reasoning_effort: resolved_effort, mode: catalog_route.mode)
      when :claude
        env_provider = Sway::Settings.llm.llm_provider.to_s.strip
        case env_provider
        when "claude"
          Route.new(provider: :claude, api_model: catalog_route.api_model, reasoning_effort: resolved_effort, mode: catalog_route.mode)
        when "llamacpp"
          Route.new(provider: :llamacpp, api_model: Sway::Settings.llm.llamacpp_model, reasoning_effort: resolved_effort, mode: catalog_route.mode)
        else
          raise UnknownRouteError, "unsupported environment llm_provider: #{env_provider.inspect}"
        end
      when :llamacpp
        Route.new(provider: :llamacpp, api_model: catalog_route.api_model, reasoning_effort: resolved_effort, mode: catalog_route.mode)
      else
        raise UnknownRouteError, "unknown catalog provider: #{catalog_route.provider.inspect}"
      end
    end
  end
end
