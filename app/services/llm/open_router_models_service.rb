# frozen_string_literal: true

module Llm
  # @lat: [[open-router-models#OpenRouter models catalog]]
  class OpenRouterModelsService
    MODELS_ENDPOINT = "https://openrouter.ai/api/v1/models?supported_parameters=structured_outputs"
    DECISION_MODELS_ENDPOINT = "https://openrouter.ai/api/v1/models?output_modalities=decisions"
    CACHE_KEY = "llm/openrouter/structured_output_models/v1"
    DECISION_CACHE_KEY = "llm/openrouter/decision_models/v1"
    CACHE_TTL = 12.hours
    OPEN_TIMEOUT_SECONDS = 5
    READ_TIMEOUT_SECONDS = 10
    SLUG_PATTERN = %r{\A(?!.*\.\.)~?[a-zA-Z0-9][a-zA-Z0-9._-]*/[a-zA-Z0-9][a-zA-Z0-9._:-]*\z}

    def self.call(force_refresh: false)
      unless force_refresh
        cached = read_cache
        return cached if cached
      end

      fresh = fetch_from_api
      if fresh
        write_cache(fresh)
        fresh
      else
        read_cache || [].freeze
      end
    end

    def self.decision_models(force_refresh: false)
      unless force_refresh
        cached = read_decision_cache
        return cached if cached
      end

      fresh = fetch_decision_models_from_api
      if fresh
        write_decision_cache(fresh)
        fresh
      else
        read_decision_cache || [].freeze
      end
    end

    def self.lookup(model_id, models: nil)
      id = model_id.to_s.strip
      return nil if id.blank?

      (models || call).find { |m| m[:id] == id }
    end

    def self.lookup_decision_model(model_id, models: nil)
      id = model_id.to_s.strip
      return nil if id.blank?

      (models || decision_models).find { |m| m[:id] == id }
    end

    def self.valid_slug?(model_id)
      SLUG_PATTERN.match?(model_id.to_s.strip)
    end

    private_class_method def self.fetch_data_from_endpoint(endpoint)
      response = connection.get(endpoint)
      raise Faraday::ServerError, "unexpected HTTP status #{response.status}" unless response.status == 200

      parsed = JSON.parse(response.body)
      data = parsed["data"]
      raise StandardError, "missing data array in response" unless data.is_a?(Array)

      data
    rescue => e
      Rails.logger.warn("Llm::OpenRouterModelsService failed to fetch models: #{e.class}: #{e.message}")
      nil
    end

    private_class_method def self.fetch_from_api
      data = fetch_data_from_endpoint(MODELS_ENDPOINT)
      data ? normalize_models(data) : nil
    end

    private_class_method def self.fetch_decision_models_from_api
      data = fetch_data_from_endpoint(DECISION_MODELS_ENDPOINT)
      data ? normalize_decision_models(data) : nil
    end

    private_class_method def self.normalize_models(raw_items)
      models = []
      seen_ids = Set.new

      raw_items.each do |item|
        next unless item.is_a?(Hash)

        raw_id = item["id"]
        next unless raw_id.is_a?(String)

        id = raw_id.strip
        next unless valid_slug?(id)
        next if seen_ids.include?(id)

        if item.key?("supported_parameters") && item["supported_parameters"].is_a?(Array)
          next unless item["supported_parameters"].include?("structured_outputs")
        end

        label = item.fetch("name", "").to_s.strip.presence || id
        supports_reasoning = extract_reasoning_support(item)

        seen_ids.add(id)
        models << {
          id: id,
          label: label,
          supports_reasoning: supports_reasoning
        }.freeze
      end

      models.sort_by! { |m| [m[:label].downcase, m[:id]] }
      models.freeze
    end

    private_class_method def self.normalize_decision_models(raw_items)
      models = []
      seen_ids = Set.new

      raw_items.each do |item|
        next unless item.is_a?(Hash)

        raw_id = item["id"]
        next unless raw_id.is_a?(String)

        id = raw_id.strip
        next unless valid_slug?(id)
        next if seen_ids.include?(id)

        arch = item["architecture"]
        if item.key?("architecture") && !arch.nil?
          next unless arch.is_a?(Hash) && arch["output_modalities"].is_a?(Array) && arch["output_modalities"].include?("decisions")
        end

        label = item.fetch("name", "").to_s.strip.presence || id

        seen_ids.add(id)
        models << {
          id: id,
          label: label,
          supports_reasoning: false,
          mode: :decision
        }.freeze
      end

      models.sort_by! { |m| [m[:label].downcase, m[:id]] }
      models.freeze
    end

    private_class_method def self.extract_reasoning_support(item)
      efforts = item.dig("reasoning", "supported_efforts")
      return true if efforts.is_a?(Array) && efforts.any?

      params = Array(item.fetch("supported_parameters", nil))
      params.intersect?(%w[reasoning reasoning_effort])
    end

    private_class_method def self.read_cache
      val = Rails.cache.read(CACHE_KEY)
      val.is_a?(Array) ? val : nil
    end

    private_class_method def self.write_cache(models)
      Rails.cache.write(CACHE_KEY, models, expires_in: CACHE_TTL)
    end

    private_class_method def self.read_decision_cache
      val = Rails.cache.read(DECISION_CACHE_KEY)
      val.is_a?(Array) ? val : nil
    end

    private_class_method def self.write_decision_cache(models)
      Rails.cache.write(DECISION_CACHE_KEY, models, expires_in: CACHE_TTL)
    end

    private_class_method def self.connection
      Faraday.new do |f|
        f.options.open_timeout = OPEN_TIMEOUT_SECONDS
        f.options.timeout = READ_TIMEOUT_SECONDS
        f.headers["Accept"] = "application/json"
        key = api_key
        f.headers["Authorization"] = "Bearer #{key}" if key.present?
        f.adapter Faraday.default_adapter
      end
    end

    private_class_method def self.api_key
      EnvSecret.read("OPENROUTER_API_KEY") || EnvSecret.read("OPEN_ROUTER_API_KEY")
    end
  end
end
