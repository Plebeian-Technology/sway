# frozen_string_literal: true

require "faraday"
require "json"
require "openai"

module Llm
  # @lat: [[llm-summaries#Two adapters, one client]]
  # @lat: [[llm-summaries#What a third provider reached through OpenRouter exposes#Companies permitted to receive Baltimore hearing testimony]]
  class OpenRouterAdapter
    class UnpinnedUpstreamError < Llm::TransportError; end

    DECISIONS_ENDPOINT = "https://openrouter.ai/api/alpha/decisions"

    TEMPERATURE = 0.2
    MAX_TOKENS = 4096
    ALLOWED_REASONING_EFFORTS = %w[low medium high].freeze
    REASONING_MAX_TOKENS = 16_384

    attr_reader :last_response, :last_usage, :last_upstream_company

    def self.request_timeout_seconds
      override = Sway::Settings.llm.openrouter_request_timeout_seconds
      override.positive? ? override : Sway::Settings::Llm.defaults.fetch("openrouter_request_timeout_seconds")
    end

    def self.api_key
      EnvSecret.read("OPENROUTER_API_KEY") || EnvSecret.read("OPEN_ROUTER_API_KEY") || raise(
        Llm::TransportError,
        "openrouter transport: OPENROUTER_API_KEY or OPEN_ROUTER_API_KEY is not set (or is blank) in this process's environment"
      )
    end

    def provider_label
      "openrouter"
    end

    def generate_bill_summary(prompt:, model:, schema:, reasoning_effort: nil)
      generate_structured(
        prompt: prompt,
        model: model,
        schema: schema,
        schema_name: "bill_summary",
        validation_schema: BILL_SUMMARY_SCHEMA,
        reasoning_effort: reasoning_effort
      )
    end

    def generate_bill_categories(prompt:, model:, schema:, reasoning_effort: nil)
      generate_structured(
        prompt: prompt,
        model: model,
        schema: schema,
        schema_name: "bill_categories",
        validation_schema: BILL_CATEGORIES_SCHEMA,
        reasoning_effort: reasoning_effort
      )
    end

    def generate_bill_positions(prompt:, model:, schema:, reasoning_effort: nil)
      generate_structured(
        prompt: prompt,
        model: model,
        schema: schema,
        schema_name: "bill_positions",
        validation_schema: BILL_POSITIONS_SCHEMA,
        reasoning_effort: reasoning_effort
      )
    end

    def generate_testimony_classification(prompt:, model:, schema:, reasoning_effort: nil)
      generate_structured(
        prompt: prompt,
        model: model,
        schema: schema,
        schema_name: "testimony_classification",
        validation_schema: TESTIMONY_CLASSIFICATION_SCHEMA,
        reasoning_effort: reasoning_effort
      )
    end

    def generate_source_kind_classification(prompt:, model:, schema:, reasoning_effort: nil)
      generate_structured(
        prompt: prompt,
        model: model,
        schema: schema,
        schema_name: "source_kind_classification",
        validation_schema: SOURCE_KIND_CLASSIFICATION_SCHEMA,
        reasoning_effort: reasoning_effort
      )
    end

    # @lat: [[testimony-stance-classification#Adapter method contracts]]
    def generate_testimony_stance_classification(prompt:, model:, schema:, reasoning_effort: nil)
      generate_structured(
        prompt: prompt,
        model: model,
        schema: schema,
        schema_name: "testimony_stance_classification",
        validation_schema: TESTIMONY_STANCE_CLASSIFICATION_SCHEMA,
        reasoning_effort: reasoning_effort
      )
    end

    # @lat: [[news-article-evidence#Grounding decisions]]
    def generate_news_claim_grounding(prompt:, model:, schema:, reasoning_effort: nil)
      generate_structured(
        prompt: prompt,
        model: model,
        schema: schema,
        schema_name: "news_claim_grounding",
        validation_schema: NEWS_CLAIM_GROUNDING_SCHEMA,
        reasoning_effort: reasoning_effort
      )
    end

    # @lat: [[llm-summaries#What a third provider reached through OpenRouter exposes#OpenRouter Decisions API transport for System One models]]
    def generate_decisions(model:, state:, questions:)
      @last_response = nil
      @last_usage = nil
      @last_upstream_company = nil

      raise ArgumentError, "model must be specified" if model.to_s.strip.empty?
      raise ArgumentError, "questions must be a non-empty Hash" unless questions.is_a?(Hash) && questions.any?

      payload = {
        model: model,
        state: state.is_a?(Hash) ? state : {},
        questions: questions,
        provider: {
          data_collection: "deny"
        }
      }

      response = decisions_connection.post(decisions_endpoint) do |req|
        req.body = payload.to_json
      end

      if response.body.to_s.strip.empty?
        raise Llm::TransportError, "openrouter transport: empty response"
      end

      parsed_response = begin
        JSON.parse(response.body)
      rescue JSON::ParserError => e
        raise Llm::SchemaError, "openrouter schema: failed to parse response JSON: #{e.message}"
      end

      unless parsed_response.is_a?(Hash)
        raise Llm::TransportError, "openrouter transport: malformed response envelope"
      end

      verify_decisions_serving_upstream!(parsed_response)
      validate_decisions_answers!(parsed_response["answers"], questions)

      SwayLogging.info(
        "openrouter.decisions.completed",
        upstream_company: @last_upstream_company,
        model: parsed_response["model"],
        requested_model: model
      )

      parsed_response
    rescue Faraday::Error => e
      side = classify_failure_side(e)
      detail = transport_error_detail(e)
      raise Llm::TransportError, "openrouter transport: #{side}: #{e.class}: #{detail}"
    end

    # @lat: [[llm-summaries#What a third provider reached through OpenRouter exposes#ScaleDown entity extraction through constrained decoding]]
    def generate_entity_extraction(model:, content:, entities:, max_tokens: nil)
      raise ArgumentError, "model must be a non-blank String" unless model.is_a?(String) && !model.strip.empty?
      raise ArgumentError, "content must be a non-blank String" unless content.is_a?(String) && !content.strip.empty?

      validate_entities_hash!(entities)

      effective_max_tokens = max_tokens || MAX_TOKENS
      parameters = {
        model: model,
        messages: [
          {role: "user", content: content.to_s}
        ],
        max_tokens: effective_max_tokens,
        provider: {
          data_collection: "deny",
          options: {
            scaledown: {
              entities: entities.transform_keys(&:to_s)
            }
          }
        }
      }

      execute_chat_completion(parameters: parameters, max_tokens: effective_max_tokens) do |message_content, response|
        parsed = begin
          JSON.parse(message_content)
        rescue JSON::ParserError => e
          raise Llm::SchemaError, "openrouter schema: failed to parse JSON content: #{e.message}"
        end

        unless parsed.is_a?(Hash)
          raise Llm::SchemaError, "openrouter schema: expected Hash of extracted entities, got #{parsed.class}"
        end

        SwayLogging.info(
          "openrouter.entity_extraction.completed",
          upstream_company: @last_upstream_company,
          model: response["model"],
          requested_model: model
        )

        parsed
      end
    end

    private

    # @lat: [[llm-summaries#What a third provider reached through OpenRouter exposes#Companies permitted to receive Baltimore hearing testimony]]
    # @lat: [[llm-summaries#What a third provider reached through OpenRouter exposes#Settled schema keyword stripping for OpenAI-shaped requests]]
    def generate_structured(prompt:, model:, schema:, schema_name:, validation_schema:, reasoning_effort: nil)
      normalized_effort = reasoning_effort.to_s.strip.presence
      if normalized_effort && !ALLOWED_REASONING_EFFORTS.include?(normalized_effort)
        raise ArgumentError, "unsupported reasoning_effort: #{reasoning_effort.inspect} (allowed: low, medium, high)"
      end

      max_tokens = normalized_effort ? REASONING_MAX_TOKENS : MAX_TOKENS

      parameters = {
        model: model,
        messages: [
          {role: "system", content: prompt.system_prompt},
          {role: "user", content: prompt.user_message}
        ],
        response_format: {
          type: "json_schema",
          json_schema: {
            name: schema_name,
            schema: Llm::StructuredOutputSchema.for_request(schema, dialect: :openai),
            strict: true
          }
        },
        temperature: TEMPERATURE,
        max_tokens: max_tokens,
        provider: {
          data_collection: "deny",
          require_parameters: true
        }
      }
      parameters[:reasoning] = {effort: normalized_effort} if normalized_effort

      execute_chat_completion(parameters: parameters, max_tokens: max_tokens) do |content, response|
        result = Llm::SchemaValidator.parse_and_validate(
          content,
          provider_label: provider_label,
          schema: validation_schema
        )

        SwayLogging.info(
          "openrouter.call.completed",
          upstream_company: @last_upstream_company,
          model: response["model"],
          requested_model: model
        )
        result
      end
    end

    def execute_chat_completion(parameters:, max_tokens:)
      @last_response = nil
      @last_usage = nil
      @last_upstream_company = nil

      response = client.chat(parameters: parameters)

      unless valid_response_envelope?(response)
        raise Llm::TransportError, "openrouter transport: malformed response envelope"
      end

      verify_serving_upstream!(response)

      finish_reason = response.dig("choices", 0, "finish_reason")
      content = response.dig("choices", 0, "message", "content")
      if finish_reason == "length"
        raise Llm::SchemaError,
          "openrouter schema: response truncated — hit max_tokens=#{max_tokens} (finish_reason=length, content_bytes=#{content.to_s.bytesize})"
      end

      raise Llm::TransportError, "openrouter transport: empty response" if content.to_s.strip.empty?

      yield content, response
    rescue Faraday::Error, OpenAI::Error => e
      side = classify_failure_side(e)
      detail = transport_error_detail(e)
      raise Llm::TransportError, "openrouter transport: #{side}: #{e.class}: #{detail}"
    end

    def verify_decisions_serving_upstream!(response)
      unless response.is_a?(Hash)
        raise UnpinnedUpstreamError, "openrouter transport: response omitted serving upstream company attribution"
      end

      serving = extract_serving_upstream(response)

      if serving.blank?
        claims = []
        add_attribution_claim!(claims, response["provider"]) if response.key?("provider")
        add_attribution_claim!(claims, response["provider_name"]) if response.key?("provider_name")

        if claims.empty?
          raise UnpinnedUpstreamError, "openrouter transport: response omitted serving upstream company attribution"
        end

        if claims.map(&:downcase).uniq.length > 1
          raise UnpinnedUpstreamError, "openrouter transport: conflicting serving upstream company attribution"
        end

        serving = claims.first
      end

      if serving.blank?
        raise UnpinnedUpstreamError, "openrouter transport: response omitted serving upstream company attribution"
      end

      @last_upstream_company = serving
      @last_response = response
      @last_usage = response["usage"]
    end

    def validate_decisions_answers!(answers, questions)
      unless answers.is_a?(Hash) && answers.present?
        raise Llm::SchemaError, "openrouter schema: answers must be a non-empty Hash"
      end

      question_keys = questions.keys.map(&:to_s)
      answers_keys = answers.keys.map(&:to_s)
      missing_keys = question_keys - answers_keys
      if missing_keys.any?
        raise Llm::SchemaError, "openrouter schema: missing answers for questions: #{missing_keys.join(", ")}"
      end

      question_keys.each do |q_key|
        question = questions[q_key] || questions[q_key.to_sym] || {}
        answer = answers[q_key] || answers[q_key.to_sym]

        unless answer.is_a?(Hash)
          raise Llm::SchemaError, "openrouter schema: answer for #{q_key} must be a Hash"
        end

        q_type = (question["type"] || question[:type]).to_s
        ans_type = (answer["type"] || answer[:type]).to_s

        if q_type.present? && ans_type != q_type
          raise Llm::SchemaError, "openrouter schema: question #{q_key} expects type #{q_type}, got #{ans_type}"
        end

        case ans_type
        when "choice"
          choice_val = answer["choice"] || answer[:choice]
          probs = answer["probabilities"] || answer[:probabilities]
          unless choice_val.is_a?(String) && choice_val.present?
            raise Llm::SchemaError, "openrouter schema: choice answer for #{q_key} must have a non-blank String 'choice'"
          end
          unless probs.is_a?(Hash)
            raise Llm::SchemaError, "openrouter schema: choice answer for #{q_key} must have a Hash 'probabilities'"
          end

          valid_probs = probs.values.all? do |v|
            v.is_a?(Numeric) && (!v.is_a?(Float) || v.finite?) && v >= 0.0 && v <= 1.0
          end
          unless valid_probs
            raise Llm::SchemaError, "openrouter schema: choice answer for #{q_key} must have numeric probabilities between 0.0 and 1.0"
          end

          confidence = answer.key?("confidence") ? answer["confidence"] : answer[:confidence]
          if !confidence.nil? && !(confidence.is_a?(Numeric) && (!confidence.is_a?(Float) || confidence.finite?) && confidence >= 0.0 && confidence <= 1.0)
            raise Llm::SchemaError, "openrouter schema: choice answer for #{q_key} must have a Numeric 'confidence' between 0.0 and 1.0"
          end

          criteria = question["criteria"] || question[:criteria]
          if criteria.is_a?(Hash) && criteria.present?
            allowed_choices = criteria.keys.map(&:to_s)
            unless allowed_choices.include?(choice_val.to_s)
              raise Llm::SchemaError, "openrouter schema: choice #{choice_val.inspect} for #{q_key} is not in criteria choices: #{allowed_choices.join(", ")}"
            end
          end
        when "noul"
          noul_val = answer["noul"] || answer[:noul]
          is_valid_noul = noul_val.is_a?(Numeric) && (!noul_val.is_a?(Float) || noul_val.finite?) && noul_val >= 0.0 && noul_val <= 1.0
          unless is_valid_noul
            raise Llm::SchemaError, "openrouter schema: noul answer for #{q_key} must have a Numeric 'noul' probability between 0.0 and 1.0"
          end
        when "score"
          score_val = answer["score"] || answer[:score]
          is_valid_score = (score_val.is_a?(Numeric) && (!score_val.is_a?(Float) || score_val.finite?)) ||
            (score_val.is_a?(String) && !score_val.strip.empty?)
          unless is_valid_score
            raise Llm::SchemaError, "openrouter schema: score answer for #{q_key} must have a Numeric or String 'score'"
          end
        else
          raise Llm::SchemaError, "openrouter schema: unrecognized answer type #{ans_type.inspect} for #{q_key}"
        end
      end
    end

    def validate_entities_hash!(entities)
      unless entities.is_a?(Hash) && entities.any?
        raise ArgumentError, "entities must be a non-empty Hash"
      end

      entities.each do |key, description|
        is_valid_key = (key.is_a?(String) || key.is_a?(Symbol)) && key.to_s.present?
        raise ArgumentError, "entity key must be a non-blank String or Symbol" unless is_valid_key

        unless description.is_a?(String) && description.strip.present?
          raise ArgumentError, "entity description for #{key.inspect} must be a non-blank String"
        end
      end
    end

    def decisions_endpoint
      base = Sway::Settings.llm.openrouter_base_url.to_s.strip
      return DECISIONS_ENDPOINT if base.blank?

      if base.match?(%r{/alpha/decisions/?\z})
        base.sub(%r{/\z}, "")
      elsif base.match?(%r{/v1/?\z})
        base.sub(%r{/v1/?\z}, "/alpha/decisions")
      else
        "#{base.sub(%r{/\z}, "")}/alpha/decisions"
      end
    end

    def decisions_connection
      Faraday.new do |conn|
        conn.request :retry, Sway::FaradayStack::OPENROUTER_DEFAULTS
        conn.response :raise_error
        conn.options.timeout = self.class.request_timeout_seconds
        conn.headers["Authorization"] = "Bearer #{self.class.api_key}"
        conn.headers["Content-Type"] = "application/json"
        conn.headers["Accept"] = "application/json"
        conn.headers["X-OpenRouter-Metadata"] = "enabled"
        conn.adapter Faraday.default_adapter
      end
    end

    def verify_serving_upstream!(response)
      serving = extract_serving_upstream(response)
      if serving.blank?
        raise UnpinnedUpstreamError, "openrouter transport: response omitted serving upstream company attribution"
      end

      @last_upstream_company = serving
      @last_response = response
      @last_usage = response["usage"]
    end

    def extract_serving_upstream(response)
      return nil unless response.is_a?(Hash)

      openrouter_metadata = response["openrouter_metadata"]
      return nil unless openrouter_metadata.is_a?(Hash)

      endpoints = openrouter_metadata["endpoints"]
      return nil if openrouter_metadata.key?("endpoints") && !endpoints.is_a?(Hash)

      available_endpoints = endpoints["available"] if endpoints.is_a?(Hash)
      available_endpoints = openrouter_metadata["available_endpoints"] unless available_endpoints.is_a?(Array)
      return nil unless available_endpoints.is_a?(Array)

      selected_endpoints = available_endpoints.select { |endpoint| endpoint.is_a?(Hash) && endpoint["selected"] == true }
      return nil unless selected_endpoints.one?

      selected_provider = selected_endpoints.first["provider"]
      return nil unless selected_provider.is_a?(String) && selected_provider.present?

      claims = [selected_provider]
      if (attempts = openrouter_metadata["attempts"]).is_a?(Array) && attempts.any?
        last_attempt = attempts.last
        return nil unless last_attempt.is_a?(Hash)

        add_attribution_claim!(claims, last_attempt["provider"]) if last_attempt.key?("provider")
      end
      add_attribution_claim!(claims, openrouter_metadata["provider"]) if openrouter_metadata.key?("provider")
      add_attribution_claim!(claims, response["provider_name"]) if response.key?("provider_name")
      add_attribution_claim!(claims, response["provider"]) if response.key?("provider")

      if claims.map(&:downcase).uniq.length > 1
        raise UnpinnedUpstreamError, "openrouter transport: conflicting serving upstream company attribution"
      end

      selected_provider
    end

    def add_attribution_claim!(claims, provider)
      return if provider.nil? || provider == ""

      unless provider.is_a?(String)
        raise UnpinnedUpstreamError, "openrouter transport: omitted serving upstream company attribution"
      end

      claims << provider
    end

    def valid_response_envelope?(response)
      return false unless response.is_a?(Hash)

      choices = response["choices"]
      return false unless choices.is_a?(Array) && choices.first.is_a?(Hash)

      message = choices.first["message"]
      return false unless message.is_a?(Hash)

      content = message["content"]
      content.nil? || content.is_a?(String)
    end

    def classify_failure_side(error)
      if error.is_a?(Faraday::TimeoutError) || error.is_a?(Faraday::ConnectionFailed) || error.is_a?(Faraday::SSLError)
        return "routing service"
      end

      status = error.respond_to?(:response_status) ? error.response_status : nil
      status ||= error.response[:status] if error.respond_to?(:response) && error.response.is_a?(Hash)

      body = error.respond_to?(:response_body) ? error.response_body : nil
      body ||= error.response[:body] if error.respond_to?(:response) && error.response.is_a?(Hash)

      return "routing service" if [401, 402, 403, 408].include?(status)

      if body.is_a?(Hash)
        error_obj = body["error"]
        if error_obj.is_a?(Hash)
          metadata = error_obj["metadata"]
          if metadata.is_a?(Hash) && (metadata["provider_name"].present? || metadata["raw"].present?)
            return "model"
          end
          msg = error_obj["message"].to_s
          return "model" if msg.match?(/upstream|provider|model/i)
        end
      elsif body.is_a?(String)
        return "model" if body.match?(/upstream|provider|model/i)
      end

      return "model" if [502, 503].include?(status)

      "routing service"
    end

    def transport_error_detail(error)
      body = error.respond_to?(:response_body) ? error.response_body : nil
      body ||= error.response[:body] if error.respond_to?(:response) && error.response.is_a?(Hash)

      if body.is_a?(Hash)
        error_obj = body["error"]
        if error_obj.is_a?(Hash)
          msg = error_obj["message"].to_s
          code = error_obj["code"]
          metadata = error_obj["metadata"]
          provider = metadata["provider_name"] if metadata.is_a?(Hash)
          parts = [code, msg, provider ? "provider=#{provider}" : nil].compact
          return parts.join(" - ")[0, 400]
        end
      end

      text = body.is_a?(String) ? body : body&.to_json
      text = error.message if text.to_s.strip.empty?
      text.to_s[0, 400]
    end

    def client
      @client ||= OpenAI::Client.new(
        uri_base: Sway::Settings.llm.openrouter_base_url,
        access_token: self.class.api_key,
        request_timeout: self.class.request_timeout_seconds,
        extra_headers: {
          "X-OpenRouter-Metadata" => "enabled"
        }
      ) do |connection|
        connection.request(:retry, Sway::FaradayStack::OPENROUTER_DEFAULTS)
      end
    end
  end

  UnpinnedUpstreamError = OpenRouterAdapter::UnpinnedUpstreamError
end
