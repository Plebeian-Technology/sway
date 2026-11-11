# frozen_string_literal: true

module Sway
  # @lat: [[utf8-scrub-rationale#Why String.encode does not work here]]
  module Utf8
    # @lat: [[utf8-scrub-rationale#Why invalid bytes become U+FFFD rather than an empty string]]
    REPLACEMENT = "�"

    # @lat: [[utf8-scrub-rationale#Why scrub is lossy only where necessary]]
    def self.scrub(text)
      string = text.to_s
      string = string.dup.force_encoding(Encoding::UTF_8) unless string.encoding == Encoding::UTF_8
      return string if string.valid_encoding?

      string.scrub(REPLACEMENT)
    end
  end
end
