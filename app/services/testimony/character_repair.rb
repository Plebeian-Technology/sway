# frozen_string_literal: true

module Testimony
  # @lat: [[testimony-character-repair-break-glyphs#The glyphs, and how each was found]]
  # @lat: [[testimony-character-repair-break-glyphs#Why character repair requires adjacent ASCII letters and seeds the banner vocabulary]]
  class CharacterRepair
    # @lat: [[testimony-character-repair-break-glyphs#The two-tier corroboration rule]]
    BREAK_GLYPHS = [Sway::Utf8::REPLACEMENT, "$", "?", "\\", "\u{019F}"].freeze

    # @lat: [[testimony-character-repair-break-glyphs#The two-tier corroboration rule]]
    CANDIDATE_PAIRS = %w[ti tt ff fi fl ffi ffl].freeze

    # @lat: [[testimony-character-repair-break-glyphs#The two-tier corroboration rule]]
    FALLBACK_PAIR = "ti"

    PER_POSITION_BREAK_CAP = 3

    Result = Data.define(:text, :broken_words, :resolved_from_bundle, :resolved_by_fallback, :left_unresolved)

    # @lat: [[testimony-character-repair-break-glyphs#Why the fix generalizes instead of special-casing each glyph]]
    WORD_OR_BREAK_RUN = /[A-Za-z#{BREAK_GLYPHS.map { |glyph| Regexp.escape(glyph) }.join}]+/

    CLEAN_WORD_RUN = /[A-Za-z]+/

    # @lat: [[testimony-character-repair-break-glyphs#Why character repair requires adjacent ASCII letters and seeds the banner vocabulary]]
    SEED_VOCABULARY = Testimony::BoilerplateRemover::CITY_IT_BANNER.scan(CLEAN_WORD_RUN).to_set #: Set[String]

    class << self
      def call(text)
        new(text).call
      end
    end

    def initialize(text)
      @text = text.to_s
      # @lat: [[rbs-signatures#Why a provably-safe value still needs a guard]]
      # @type var scanned_words: Array[String]
      scanned_words = []
      @text.scan(CLEAN_WORD_RUN).each { |match| scanned_words << match if match.is_a?(String) }
      @vocabulary = SEED_VOCABULARY | scanned_words.to_set
    end

    def call
      broken_words = 0
      resolved_from_bundle = 0
      resolved_by_fallback = 0
      left_unresolved = 0

      repaired = @text.gsub(WORD_OR_BREAK_RUN) do |run|
        outcome = repair_run(run)
        next run if outcome.nil?

        broken_words += 1
        case outcome[:kind]
        when :from_bundle then resolved_from_bundle += 1
        when :fallback then resolved_by_fallback += 1
        when :unresolved then left_unresolved += 1
        end
        outcome[:text]
      end

      Result.new(
        text: repaired,
        broken_words: broken_words,
        resolved_from_bundle: resolved_from_bundle,
        resolved_by_fallback: resolved_by_fallback,
        left_unresolved: left_unresolved
      )
    end

    private

    # @lat: [[testimony-character-repair-break-glyphs#Why character repair requires adjacent ASCII letters and seeds the banner vocabulary]]
    def repair_run(run)
      chars = run.chars
      reparable = reparable_indices(chars)
      return nil if reparable.empty?

      tuples = if reparable.length <= PER_POSITION_BREAK_CAP
        CANDIDATE_PAIRS.repeated_permutation(reparable.length)
      else
        CANDIDATE_PAIRS.map { |pair| [pair] * reparable.length }
      end

      matches = tuples.filter_map { |pairs|
        candidate = substitute(chars, reparable, pairs)
        candidate if @vocabulary.include?(candidate)
      }.uniq
      return {text: matches.first, kind: :from_bundle} if matches.length == 1

      # @lat: [[testimony-character-repair-break-glyphs#The two-tier corroboration rule]]
      return {text: run, kind: :unresolved} unless reparable.all? { |i| chars[i] == Sway::Utf8::REPLACEMENT }

      {text: substitute(chars, reparable, [FALLBACK_PAIR] * reparable.length), kind: :fallback}
    end

    # @lat: [[testimony-character-repair-break-glyphs#Why character repair requires adjacent ASCII letters and seeds the banner vocabulary]]
    def reparable_indices(chars)
      (1..(chars.length - 2)).select do |i|
        BREAK_GLYPHS.include?(chars[i]) &&
          chars[i - 1].match?(/[A-Za-z]/) &&
          chars[i + 1].match?(/[A-Za-z]/)
      end
    end

    def substitute(chars, indices, pairs)
      mapping = indices.zip(pairs).to_h
      chars.each_with_index.map { |char, index| mapping.key?(index) ? mapping[index] : char }.join
    end
  end
end
