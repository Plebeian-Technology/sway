# frozen_string_literal: true

module Llm
  # @lat: [[prompt-label-design#Why scrubbing has to run first]]
  module PromptLabel
    def self.collapse(value)
      Sway::Utf8.scrub(value).gsub(/[[:space:]]+/, " ").strip
    end
  end
end
