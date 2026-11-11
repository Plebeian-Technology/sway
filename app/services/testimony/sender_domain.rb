# frozen_string_literal: true

module Testimony
  # @lat: [[testimony-letters#Why SenderDomain and SenderReader enforce separate address and domain contracts]]
  module SenderDomain
    MAX_CHARS = 253

    # @lat: [[testimony-letters#Why SenderDomain and SenderReader enforce separate address and domain contracts]]
    FORMAT = /\A[a-z0-9]([a-z0-9\-.]*[a-z0-9])?\z/

    class << self
      def valid?(candidate)
        value = candidate.to_s
        return false if value.empty?
        return false if value.length > MAX_CHARS

        FORMAT.match?(value)
      end

      # @lat: [[testimony-letters#Why SenderDomain and SenderReader enforce separate address and domain contracts]]
      def from_address(address)
        candidate = address.to_s.rpartition("@").last.downcase.sub(/[.,;:!?]+\z/, "")
        valid?(candidate) ? candidate : nil
      end
    end
  end
end
