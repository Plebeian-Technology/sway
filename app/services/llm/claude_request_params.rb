# frozen_string_literal: true

module Llm
  # @lat: [[lat.md/explanation/llm-summaries#Batch summarisation]]
  module ClaudeRequestParams
    MAX_TOKENS = 4096

    def self.build(prompt:, model:, schema:)
      {
        model: model,
        max_tokens: MAX_TOKENS,
        system: [system_block(prompt.system_prompt, model)],
        messages: [
          {role: "user", content: prompt.user_message}
        ],
        **structured_output_args(schema)
      }
    end

    def self.system_block(system_prompt, model)
      # @type var block: Hash[Symbol, untyped]
      block = {type: "text", text: system_prompt}
      cache_control = Llm::PromptCache.cache_control_for(system_prompt, model: model)
      block[:cache_control] = cache_control if cache_control
      block
    end
    private_class_method :system_block

    def self.structured_output_args(schema)
      {
        output_config: {
          format: {type: "json_schema", schema: Llm::StructuredOutputSchema.for_request(schema)}
        }
      }
    end
    private_class_method :structured_output_args
  end
end
