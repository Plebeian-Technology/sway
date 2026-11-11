# frozen_string_literal: true

# @lat: [[claude-adapter-design#The four ceiling constants]]
require "anthropic"

module Llm
  # @lat: [[claude-adapter-design#structured_output_args: where schema-stripping happens]]
  class ClaudeAdapter
    # @lat: [[claude-adapter-design#The four ceiling constants]]
    MAX_TOKENS = Llm::ClaudeRequestParams::MAX_TOKENS

    DEFAULT_TIMEOUT_SECONDS = Llm::ClaudeConnection::DEFAULT_TIMEOUT_SECONDS

    DEFAULT_MAX_RETRIES = Llm::ClaudeConnection::DEFAULT_MAX_RETRIES

    MAX_TRANSLATED_ERROR_LENGTH = Llm::ClaudeErrorTranslation::MAX_TRANSLATED_ERROR_LENGTH

    attr_reader :last_usage, :last_response

    def provider_label
      "claude"
    end

    # @lat: [[claude-adapter-design#The generate_* public methods all route through one private body]]
    def generate_bill_summary(prompt:, model:, schema:)
      generate_structured(prompt: prompt, model: model, schema: schema, validation_schema: BILL_SUMMARY_SCHEMA)
    end

    # @lat: [[claude-adapter-design#The generate_* public methods all route through one private body]]
    def generate_bill_categories(prompt:, model:, schema:)
      generate_structured(prompt: prompt, model: model, schema: schema, validation_schema: BILL_CATEGORIES_SCHEMA)
    end

    # @lat: [[claude-adapter-design#The generate_* public methods all route through one private body]]
    def generate_bill_positions(prompt:, model:, schema:)
      generate_structured(prompt: prompt, model: model, schema: schema, validation_schema: BILL_POSITIONS_SCHEMA)
    end

    # @lat: [[claude-adapter-design#The generate_* public methods all route through one private body]]
    def generate_testimony_classification(prompt:, model:, schema:)
      generate_structured(prompt: prompt, model: model, schema: schema, validation_schema: TESTIMONY_CLASSIFICATION_SCHEMA)
    end

    # @lat: [[claude-adapter-design#The generate_* public methods all route through one private body]]
    def generate_source_kind_classification(prompt:, model:, schema:)
      generate_structured(prompt: prompt, model: model, schema: schema, validation_schema: SOURCE_KIND_CLASSIFICATION_SCHEMA)
    end

    # @lat: [[testimony-stance-classification#Adapter method contracts]]
    def generate_testimony_stance_classification(prompt:, model:, schema:)
      generate_structured(prompt: prompt, model: model, schema: schema, validation_schema: TESTIMONY_STANCE_CLASSIFICATION_SCHEMA)
    end

    # @lat: [[news-article-evidence#Grounding decisions]]
    def generate_news_claim_grounding(prompt:, model:, schema:)
      generate_structured(prompt: prompt, model: model, schema: schema, validation_schema: NEWS_CLAIM_GROUNDING_SCHEMA)
    end

    private

    # @lat: [[lat.md/explanation/llm-summaries#Talking to the Anthropic SDK]]
    def generate_structured(prompt:, model:, schema:, validation_schema:)
      Llm::ClaudeErrorTranslation.translate do
        response = client.messages.create(
          request_options: {timeout: DEFAULT_TIMEOUT_SECONDS},
          **Llm::ClaudeRequestParams.build(prompt: prompt, model: model, schema: schema)
        )

        @last_response = response
        @last_usage = response.usage
        record_usage(response, fallback_model: model)

        Llm::SchemaValidator.parse_and_validate(
          Llm::ClaudeMessageText.extract(response),
          provider_label: provider_label,
          schema: validation_schema
        )
      end
    end

    def record_usage(response, fallback_model:)
      return unless response.respond_to?(:usage)

      usage = response.usage
      return if usage.nil?

      model_name = if response.respond_to?(:model) && response.model.present?
        response.model
      else
        fallback_model
      end

      metadata = {
        model: model_name,
        input_tokens: usage.input_tokens.to_i,
        output_tokens: usage.output_tokens.to_i
      }

      if usage.respond_to?(:cache_creation_input_tokens) && usage.cache_creation_input_tokens
        metadata[:cache_creation_input_tokens] = usage.cache_creation_input_tokens.to_i
      end
      if usage.respond_to?(:cache_read_input_tokens) && usage.cache_read_input_tokens
        metadata[:cache_read_input_tokens] = usage.cache_read_input_tokens.to_i
      end

      SwayLogging.info("claude.usage.recorded", **metadata)
    end

    # @lat: [[claude-adapter-design#client: built once per adapter instance]]
    def client
      @client ||= Llm::ClaudeConnection.build
    end
  end
end
