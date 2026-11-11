# frozen_string_literal: true

module Llm
  # @lat: [[lat.md/explanation/llm-summaries#Batch summarisation#Two traps in the gem]]
  module BatchCustomId
    PATTERN = /\A[a-zA-Z0-9_-]{1,64}\z/
    TRUNCATED_PREFIX_LENGTH = 55
    HASH_SUFFIX_LENGTH = 8

    def self.build(*parts)
      sanitized = parts.join("__").gsub(/[^a-zA-Z0-9_-]+/, "-")
      return sanitized if sanitized.length <= 64

      digest = Digest::SHA256.hexdigest(sanitized)[0, HASH_SUFFIX_LENGTH]
      "#{sanitized[0, TRUNCATED_PREFIX_LENGTH]}-#{digest}"
    end

    def self.valid?(id)
      id.to_s.match?(PATTERN)
    end
  end
end
