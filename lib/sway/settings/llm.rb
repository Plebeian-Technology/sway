# frozen_string_literal: true

module Sway
  module Settings
    # @lat: [[llm-settings-group-design#The Rails.env.development? class-body timing]]
    class Llm < Base
      config_name "llm"
      env_prefix ""

      attr_config llm_provider: "llamacpp"
      coerce_types llm_provider: :string
      required :llm_provider

      attr_config llamacpp_model: "local"
      coerce_types llamacpp_model: :string
      required :llamacpp_model

      attr_config llamacpp_base_url: "http://host.docker.internal:8888/v1"
      coerce_types llamacpp_base_url: :string
      required :llamacpp_base_url

      attr_config openrouter_base_url: "https://openrouter.ai/api/v1"
      coerce_types openrouter_base_url: :string
      required :openrouter_base_url

      attr_config llm_llamacpp_thinking: false
      coerce_types llm_llamacpp_thinking: :boolean
      required :llm_llamacpp_thinking

      attr_config llm_request_timeout_seconds: 120
      coerce_types llm_request_timeout_seconds: :integer
      required :llm_request_timeout_seconds

      attr_config openrouter_request_timeout_seconds: 120
      coerce_types openrouter_request_timeout_seconds: :integer
      required :openrouter_request_timeout_seconds

      attr_config llm_max_source_chars: (Rails.env.development? ? 45_000 : 300_000)
      coerce_types llm_max_source_chars: :integer
      required :llm_max_source_chars

      attr_config llm_max_testimony_tokens: (Rails.env.development? ? 30_000 : 90_000)
      coerce_types llm_max_testimony_tokens: :integer
      required :llm_max_testimony_tokens

      attr_config llm_max_testimony_chars: (Rails.env.development? ? 45_000 : 150_000)
      coerce_types llm_max_testimony_chars: :integer
      required :llm_max_testimony_chars

      attr_config llm_max_summary_context_chars: 4_000
      coerce_types llm_max_summary_context_chars: :integer
      required :llm_max_summary_context_chars

      # @lat: [[reference/bill-positions-prompt-limits#The limits]]
      attr_config llm_max_positions_chunks: 10
      coerce_types llm_max_positions_chunks: :integer
      required :llm_max_positions_chunks

      # @lat: [[settings-groups#Why the freeze runs after a group's own repair]]
      on_load { self.class.freeze_mutable_attributes!(self) }
    end
  end
end
