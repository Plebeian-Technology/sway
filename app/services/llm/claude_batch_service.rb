# frozen_string_literal: true

module Llm
  # @lat: [[lat.md/explanation/llm-summaries#Batch summarisation]]
  class ClaudeBatchService
    Item = Data.define(:custom_id, :prompt, :model, :schema, :validation_schema)
    Result = Data.define(:custom_id, :value, :error, :usage, :model)

    DEFAULT_MAX_RETRIES = Llm::ClaudeConnection::DEFAULT_MAX_RETRIES
    DEFAULT_TIMEOUT_SECONDS = Llm::ClaudeConnection::DEFAULT_TIMEOUT_SECONDS
    BATCH_RESULTS_TIMEOUT_SECONDS = Llm::ClaudeConnection::BATCH_RESULTS_TIMEOUT_SECONDS
    MAX_TRANSLATED_ERROR_LENGTH = Llm::ClaudeErrorTranslation::MAX_TRANSLATED_ERROR_LENGTH

    # @lat: [[llm-summaries#Batch summarisation#A purchase is sent exactly once]]
    SUBMIT_MAX_RETRIES = 0

    class << self
      # @lat: [[lat.md/explanation/llm-summaries#Batch summarisation#Two traps in the gem]]
      def submit(items:)
        invalid_ids = items.map(&:custom_id).reject { |id| Llm::BatchCustomId.valid?(id) }
        if invalid_ids.any?
          raise ArgumentError, "invalid custom_id(s), must match '#{Llm::BatchCustomId::PATTERN.source}': " \
            "#{invalid_ids.map(&:inspect).join(", ")}"
        end

        Llm::ClaudeErrorTranslation.translate do
          client.messages.batches.create(
            requests: items.map { |item|
              {
                custom_id: item.custom_id,
                params: Llm::ClaudeRequestParams.build(prompt: item.prompt, model: item.model, schema: item.schema)
              }
            },
            request_options: {max_retries: SUBMIT_MAX_RETRIES}
          )
        end
      end

      def status(batch_id:)
        Llm::ClaudeErrorTranslation.translate { client.messages.batches.retrieve(batch_id) }
      end

      def cancel(batch_id:)
        Llm::ClaudeErrorTranslation.translate { client.messages.batches.cancel(batch_id) }
      end

      # @lat: [[lat.md/explanation/llm-summaries#Batch summarisation]]
      def results(batch_id:, items_by_custom_id:)
        Llm::ClaudeErrorTranslation.translate do
          client.messages.batches.results_streaming(
            batch_id, request_options: {timeout: BATCH_RESULTS_TIMEOUT_SECONDS}
          ).each_with_object({}) do |individual, out|
            item = items_by_custom_id[individual.custom_id] #: Llm::ClaudeBatchService::Item?
            out[individual.custom_id] =
              item.nil? ? unknown_custom_id_result(individual.custom_id) : mapped_result(individual, item)
          end
        end
      end

      private

      # @lat: [[llm-summaries#Batch summarisation#Why an unknown custom_id is an error, not an exception]]
      def unknown_custom_id_result(custom_id)
        Result.new(
          custom_id: custom_id, value: nil,
          error: Llm::TransportError.new("claude transport: unknown custom_id #{custom_id.inspect}"),
          usage: nil, model: nil
        )
      end

      # @lat: [[llm-summaries#Batch summarisation#Why results are collected rather than raised]]
      def mapped_result(individual, item)
        map_result(individual, item)
      rescue => e
        Result.new(
          custom_id: individual.custom_id, value: nil,
          error: Llm::TransportError.new("claude transport: unmappable result envelope (#{e.class.name})"),
          usage: nil, model: nil
        )
      end

      def map_result(individual, item)
        result = individual.result
        case result.type.to_s
        when "succeeded"
          map_succeeded(result.message, item)
        when "errored"
          Result.new(custom_id: individual.custom_id, value: nil, error: errored_result_error(result), usage: nil, model: nil)
        when "canceled"
          Result.new(custom_id: individual.custom_id, value: nil, error: Llm::TransportError.new("claude transport: item canceled"), usage: nil, model: nil)
        when "expired"
          Result.new(
            custom_id: individual.custom_id, value: nil,
            error: Llm::TransportError.new("claude transport: item expired (batch exceeded 24h)"), usage: nil, model: nil
          )
        else
          Result.new(
            custom_id: individual.custom_id, value: nil,
            error: Llm::TransportError.new("claude transport: unknown result type #{result.type.inspect}"), usage: nil, model: nil
          )
        end
      end

      def map_succeeded(message, item)
        value = Llm::SchemaValidator.parse_and_validate(
          Llm::ClaudeMessageText.extract(message),
          provider_label: "claude-batch",
          schema: item.validation_schema
        )
        # @lat: [[llm-summaries#Batch summarisation#Why a result carries the model that answered]]
        Result.new(custom_id: item.custom_id, value: value, error: nil, usage: message.usage, model: message.model)
      rescue Llm::SchemaError, Llm::TransportError => e
        Result.new(custom_id: item.custom_id, value: nil, error: e, usage: nil, model: nil)
      end

      def errored_result_error(result)
        inner = result.error.error
        Llm::TransportError.new("claude transport: #{inner.type} #{inner.message.to_s[0, MAX_TRANSLATED_ERROR_LENGTH]}")
      end

      def client
        @client ||= Llm::ClaudeConnection.build
      end
    end
  end
end
