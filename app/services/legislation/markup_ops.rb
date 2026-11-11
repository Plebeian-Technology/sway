# frozen_string_literal: true

# @lat: [[legislation-pipeline#Typographic markup and declared target resolution]]
module Legislation
  module MarkupOps
    LEGEND_PATTERN = /CAPITALS\s+indicate\s+matter\s+added\s+to\s+existing\s+law[.,]?\s*\[Brackets\]\s+indicate\s+matter\s+deleted\s+from\s+existing\s+law[.,]?/i

    EXCLUSIONS = [
      /(?:EXPLANATION:\s*)?CAPITALS\s+indicate\s+matter\s+added\s+to\s+existing\s+law[.,]?\s*\[Brackets\]\s+indicate\s+matter\s+deleted\s+from\s+existing\s+law[.,]?/i,
      /(?:SECTION\s+\d+[.,]?\s+)?(?:AND\s+)?BE\s*IT\s+(?:FURTHER\s+)?ORDAINED\s+BY\s+THE\s+MAYOR\s+AND\s+CITY\s+COUNCIL\s+OF\b[^\n]*/i,
      /(?:SECTION\s+\d+[.,]?\s+)?(?:AND\s+)?BE\s*IT\s+FURTHER\s+ORDAINED\b[^\n]*/i
    ].freeze

    BRACKET_PATTERN = /\[([^\]]+)\]/
    CAPITAL_RUN_PATTERN = /\b[A-Z0-9]+(?:(?:[ \t]+|\r?\n(?!\r?\n))[A-Z0-9]+){3,}\b/

    def self.markup_fallback(text)
      return [] if text.blank? || !text.match?(LEGEND_PATTERN)

      excluded = excluded_ranges(text)
      masked_for_brackets = mask_ranges(text, excluded)

      brackets = []
      bracket_ranges = []
      masked_for_brackets.to_enum(:scan, BRACKET_PATTERN).each do
        m = ::Regexp.last_match
        next if m.nil?

        s = m.begin(0)
        e = m.end(0)
        next if s.nil? || e.nil?

        bracket_ranges << (s...e)
        brackets << {
          operation: :strike,
          anchor_text: m[1].to_s,
          source: :markup,
          char_start: s,
          char_end: e
        }
      end

      masked_for_caps = mask_ranges(masked_for_brackets, bracket_ranges)
      caps = []
      masked_for_caps.to_enum(:scan, CAPITAL_RUN_PATTERN).each do
        m = ::Regexp.last_match
        next if m.nil?

        s = m.begin(0)
        e = m.end(0)
        next if s.nil? || e.nil?

        caps << {
          operation: :insert,
          anchor_text: m[0].to_s,
          source: :markup,
          char_start: s,
          char_end: e
        }
      end

      (brackets + caps).sort_by { |op| op[:char_start].to_i }
    end

    def self.reconstruct_before_and_after(text)
      return ["", ""] if text.blank?

      excluded = excluded_ranges(text)
      masked_for_brackets = mask_ranges(text, excluded)

      brackets = []
      bracket_ranges = []
      masked_for_brackets.to_enum(:scan, BRACKET_PATTERN).each do
        m = ::Regexp.last_match
        next if m.nil?

        s = m.begin(0)
        e = m.end(0)
        next if s.nil? || e.nil?

        bracket_ranges << (s...e)
        brackets << {start: s, end: e, inner: m[1].to_s}
      end

      masked_for_caps = mask_ranges(masked_for_brackets, bracket_ranges)
      caps = []
      masked_for_caps.to_enum(:scan, CAPITAL_RUN_PATTERN).each do
        m = ::Regexp.last_match
        next if m.nil?

        s = m.begin(0)
        e = m.end(0)
        next if s.nil? || e.nil?

        caps << {start: s, end: e}
      end

      before_edits = (caps.map { |c| [c[:start], c[:end], ""] } +
                      brackets.map { |b| [b[:start], b[:end], b[:inner]] }).sort_by { |item| -item[0] }
      before_text = text.dup
      before_edits.each do |s, e, repl|
        before_text[s...e] = repl
      end

      after_edits = brackets.map { |b| [b[:start], b[:end], ""] }.sort_by { |item| -item[0] }
      after_text = text.dup
      after_edits.each do |s, e, repl|
        after_text[s...e] = repl
      end

      [before_text, after_text]
    end

    def self.excluded_ranges(text)
      ranges = []
      EXCLUSIONS.each do |pattern|
        text.to_enum(:scan, pattern).each do
          m = ::Regexp.last_match
          next if m.nil?

          s = m.begin(0)
          e = m.end(0)
          next if s.nil? || e.nil?

          ranges << (s...e)
        end
      end
      ranges
    end
    private_class_method :excluded_ranges

    def self.in_excluded_range?(char_start, char_end, ranges)
      ranges.any? { |r| char_start < r.end && char_end > r.begin }
    end
    private_class_method :in_excluded_range?

    def self.mask_ranges(text, ranges)
      masked = text.dup
      ranges.each do |r|
        masked[r] = " " * (r.end - r.begin)
      end
      masked
    end
    private_class_method :mask_ranges
  end
end
