# frozen_string_literal: true

# @lat: [[legislation-text-pattern-ops-python-port#Translating the Python regular-expression flags]]
module Legislation
  module TextPatternOps
    TEXT_PATTERN_OPS = [
      [/striking\s+.+?\s+and inserting/im, "REPLACE"],
      [/is hereby\s+(?:repealed and )?reenacted/i, "REPLACE"],
      [/is hereby repealed/i, "STRIKE"],
      [/is\s+(?:hereby\s+)?amended to read as follows/i, "INSERT"]
    ].freeze #: Array[[Regexp, String]]

    def self.text_pattern_fallback(text)
      ops = [] #: Array[op_payload]
      TEXT_PATTERN_OPS.each do |(regex, op_type)|
        text.to_enum(:scan, regex).each do
          m = ::Regexp.last_match
          next if m.nil?
          # @lat: [[rbs-signatures#Why a provably-safe value still needs a guard]]
          ops << { # steep:ignore
            operation: op_type.downcase.to_sym,
            anchor_text: m[0],
            source: :text_pattern,
            char_start: m.begin(0),
            char_end: m.end(0)
          }
        end
      end
      ops.sort_by { |op| op[:char_start].to_i }
    end
  end
end
