# frozen_string_literal: true

module Testimony
  # @lat: [[campaign-letter-disclosure#Campaign letter disclosure#Why a repeat letter is marked, not hidden]]
  # @lat: [[testimony-duplicate-letter-marking#A draft can now report fewer letters than CampaignDraftFinder::MIN_LETTERS_FOR_REUSE]]
  class DuplicateLetterMarker
    Result = Data.define(:letters)

    class << self
      def call(text:, letters:)
        new(text: text, letters: letters).call
      end
    end

    def initialize(text:, letters:)
      @text = text.to_s
      @letters = letters
    end

    def call
      seen = {}

      augmented = @letters.map do |letter|
        if letter["excluded"] == true
          next letter.merge("repeat" => false, "repeat_of_position" => nil)
        end

        address = letter["sender_address"].to_s.strip
        hash = address.empty? ? nil : body_hash(letter)

        if hash.nil?
          letter.merge("repeat" => false, "repeat_of_position" => nil)
        else
          key = [address.downcase, hash]
          earlier_position = seen[key]
          seen[key] ||= letter.fetch("position")

          letter.merge("repeat" => !earlier_position.nil?, "repeat_of_position" => earlier_position)
        end
      end

      Result.new(letters: augmented)
    end

    private

    def letter_text(letter)
      offset = letter.fetch("character_offset").to_i
      length = letter.fetch("characters").to_i
      @text[offset, length].to_s
    end

    # @lat: [[extracted-text-phrase-matching#Stripping the mail envelope by field, not by block]]
    def body_paragraphs(letter)
      envelope_stripped = Testimony::ExtractedText.strip_envelope(letter_text(letter))
      Testimony::ExtractedText.strip_recipient_headers(envelope_stripped).split(/\n[ \t]*\n+/)
    end

    def normalize(line)
      line.strip.gsub(/[ \t]+/, " ").downcase
    end

    # @lat: [[campaign-letter-disclosure#Campaign letter disclosure#Why a repeat letter is marked, not hidden]]
    def body_hash(letter)
      normalized = body_paragraphs(letter)
        .flat_map { |paragraph| paragraph.split("\n") }
        .map { |line| normalize(line) }
        .reject(&:empty?)
        .join("\n")
      return nil if normalized.empty?

      Digest::SHA256.hexdigest(normalized)
    end
  end
end
