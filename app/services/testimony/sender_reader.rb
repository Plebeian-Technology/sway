# frozen_string_literal: true

module Testimony
  # @lat: [[testimony-letters#Why SenderDomain and SenderReader enforce separate address and domain contracts]]
  class SenderReader
    SENDER_MARKER = Testimony::ExtractedText.header_line_pattern("From:")

    # @lat: [[testimony-letters#Why SenderDomain and SenderReader enforce separate address and domain contracts]]
    WINDOW_LINES = 3

    # @lat: [[testimony-letters#Why SenderDomain and SenderReader enforce separate address and domain contracts]]
    NEXT_HEADER_FIELD = /^[A-Za-z-]{2,20}:/

    # @lat: [[testimony-letters#Why SenderDomain and SenderReader enforce separate address and domain contracts]]
    ADDRESS_TOKEN = /[^\s<>,@]+@[^\s<>,@]+\.[^\s<>,@]+/

    Result = Data.define(:address, :domain)

    class << self
      def call(letter_text)
        new(letter_text).call
      end
    end

    def initialize(letter_text)
      @text = letter_text.to_s
    end

    def call
      match = SENDER_MARKER.match(@text)
      return Result.new(address: nil, domain: nil) unless match

      address = ADDRESS_TOKEN.match(window(match))&.to_s
      # @lat: [[rbs-signatures#Why a provably-safe value still needs a guard]]
      return Result.new(address: nil, domain: nil) if address.nil?
      return Result.new(address: nil, domain: nil) if address.empty?

      # @lat: [[testimony-letters#Why SenderDomain and SenderReader enforce separate address and domain contracts]]
      domain = Testimony::SenderDomain.from_address(address)
      Result.new(address: address, domain: domain)
    end

    private

    # @lat: [[testimony-letters#Why SenderDomain and SenderReader enforce separate address and domain contracts]]
    def window(match)
      lines = @text[match.end(0)..].to_s.split("\n", WINDOW_LINES + 2).first(WINDOW_LINES + 1)
      stop_at = lines.index { |line| NEXT_HEADER_FIELD.match?(line) }
      lines = lines.first(stop_at) if stop_at
      lines.join(" ").gsub(/\s*@\s*/, "@")
    end
  end
end
