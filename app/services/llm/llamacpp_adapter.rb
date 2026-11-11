# frozen_string_literal: true

require "faraday"
require "json"
require "openai"

module Llm
  # @lat: [[llamacpp-adapter-design#client: why there is no shared .llamacpp Faraday builder]]
  class LlamacppAdapter
    TEMPERATURE = 0.2
    MAX_TOKENS = 4096

    # @lat: [[llamacpp-adapter-design#.request_timeout_seconds: why 120s assumes an immediate-answering model]]
    def self.request_timeout_seconds
      override = Sway::Settings.llm.llm_request_timeout_seconds
      override.positive? ? override : Sway::Settings::Llm.defaults.fetch("llm_request_timeout_seconds")
    end

    # @lat: [[llamacpp-adapter-design#.thinking_enabled?: asking the chat template not to think first]]
    def self.thinking_enabled?
      Sway::Settings.llm.llm_llamacpp_thinking
    end

    def provider_label
      "llamacpp"
    end

    # @lat: [[claude-adapter-design#The generate_* public methods all route through one private body]]
    def generate_bill_summary(prompt:, model:, schema:)
      generate_structured(prompt: prompt, model: model, schema: schema, schema_name: "bill_summary", validation_schema: BILL_SUMMARY_SCHEMA)
    end

    # @lat: [[claude-adapter-design#The generate_* public methods all route through one private body]]
    def generate_bill_categories(prompt:, model:, schema:)
      generate_structured(prompt: prompt, model: model, schema: schema, schema_name: "bill_categories", validation_schema: BILL_CATEGORIES_SCHEMA)
    end

    # @lat: [[claude-adapter-design#The generate_* public methods all route through one private body]]
    def generate_bill_positions(prompt:, model:, schema:)
      generate_structured(prompt: prompt, model: model, schema: schema, schema_name: "bill_positions", validation_schema: BILL_POSITIONS_SCHEMA)
    end

    # @lat: [[llamacpp-adapter-design#client: why there is no shared .llamacpp Faraday builder]]
    def generate_testimony_classification(prompt:, model:, schema:)
      generate_structured(prompt: prompt, model: model, schema: schema, schema_name: "testimony_classification", validation_schema: TESTIMONY_CLASSIFICATION_SCHEMA)
    end

    # @lat: [[claude-adapter-design#The generate_* public methods all route through one private body]]
    def generate_source_kind_classification(prompt:, model:, schema:)
      generate_structured(prompt: prompt, model: model, schema: schema, schema_name: "source_kind_classification", validation_schema: SOURCE_KIND_CLASSIFICATION_SCHEMA)
    end

    # @lat: [[testimony-stance-classification#Adapter method contracts]]
    def generate_testimony_stance_classification(prompt:, model:, schema:)
      generate_structured(prompt: prompt, model: model, schema: schema, schema_name: "testimony_stance_classification", validation_schema: TESTIMONY_STANCE_CLASSIFICATION_SCHEMA)
    end

    # @lat: [[news-article-evidence#Grounding decisions]]
    def generate_news_claim_grounding(prompt:, model:, schema:)
      generate_structured(prompt: prompt, model: model, schema: schema, schema_name: "news_claim_grounding", validation_schema: NEWS_CLAIM_GROUNDING_SCHEMA)
    end

    private

    # @lat: [[llamacpp-adapter-design#generate_structured: the shared body]]
    def generate_structured(prompt:, model:, schema:, schema_name:, validation_schema:)
      response = client.chat(parameters: {
        model: model,
        messages: [
          {role: "system", content: prompt.system_prompt},
          {role: "user", content: prompt.user_message}
        ],
        # @lat: [[llamacpp-structured-output-conformance#What it pins down]]
        response_format: {
          type: "json_schema",
          json_schema: {
            name: schema_name,
            schema: schema,
            strict: true
          }
        },
        temperature: TEMPERATURE,
        max_tokens: MAX_TOKENS,
        # @lat: [[llamacpp-adapter-design#generate_structured: the shared body]]
        chat_template_kwargs: {enable_thinking: self.class.thinking_enabled?}
      })

      # @lat: [[llamacpp-adapter-design#generate_structured: the shared body#Why finish_reason is checked before content]]
      finish_reason = response.dig("choices", 0, "finish_reason")
      content = response.dig("choices", 0, "message", "content")
      if finish_reason == "length"
        raise Llm::SchemaError,
          "llama.cpp schema: response truncated — hit max_tokens=#{MAX_TOKENS} (finish_reason=length, content_bytes=#{content.to_s.bytesize})"
      end
      # @lat: [[llamacpp-adapter-design#generate_structured: the shared body]]
      raise Llm::TransportError, "llama.cpp transport: empty response" if content.to_s.strip.empty?

      # @lat: [[llamacpp-adapter-design#generate_structured: the shared body]]
      Llm::SchemaValidator.parse_and_validate(
        content,
        provider_label: "llama.cpp",
        schema: validation_schema
      )
    rescue Faraday::Error, OpenAI::Error => e
      raise Llm::TransportError, "llama.cpp transport: #{e.class}: #{transport_error_detail(e)}"
    end

    # @lat: [[llamacpp-adapter-design#client: why there is no shared .llamacpp Faraday builder]]
    def client
      @client ||= OpenAI::Client.new(
        uri_base: Sway::Settings.llm.llamacpp_base_url,
        access_token: "sk-no-key-required",
        request_timeout: self.class.request_timeout_seconds
      ) do |connection|
        connection.request(:retry, Sway::FaradayStack::LLAMACPP_DEFAULTS)
      end
    end

    # @lat: [[llamacpp-adapter-design#transport_error_detail: surfacing the response body, not just the exception class]]
    def transport_error_detail(error)
      body = (error.is_a?(Faraday::Error) ? error.response_body : nil) #: untyped
      text = body.is_a?(String) ? body : body&.to_json
      text = error.message if text.to_s.strip.empty?
      text.to_s[0, 400]
    end
  end
end
