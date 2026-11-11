# frozen_string_literal: true

module Llm
  # @lat: [[llm-prompt-payload-design#Why runtime checks exist on top of the type declaration]]
  class PromptPayload < Data.define(:system_prompt, :user_message)
    def initialize(system_prompt:, user_message:)
      unless system_prompt.is_a?(String)
        raise TypeError, "Llm::PromptPayload#system_prompt must be a String (got #{system_prompt.class})"
      end
      unless user_message.is_a?(String)
        raise TypeError, "Llm::PromptPayload#user_message must be a String (got #{user_message.class})"
      end
      super
    end
  end
end
