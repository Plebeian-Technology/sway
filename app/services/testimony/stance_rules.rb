# frozen_string_literal: true

module Testimony
  # @lat: [[testimony-letters#How CleanAndGroupService orders and threads the cleaning steps#Lexical stance rules and head-tail windowing]]
  module StanceRules
    BILL_TARGET = /(?:this\s+|the\s+|important\s+)?(?:(?:city\s+)?council\s+|senate\s+|house\s+)?(?:bill|legislation|ordinance|measure|resolution|amendment)\b|(?:council\s+)?bill\s+[#A-Z0-9-]+/i

    POSITION_HEADER_LINE_PATTERN = /\A\s*(?:position|stance)\s*:\s*(.+)\z/i
    SUBJECT_HEADER_LINE_PATTERN = /\A\s*(?:subject|re|bill|testimony)\s*:\s*(.+)\z/i

    POSITION_HEADER_OPPOSE_PATTERN = /\b(?:oppose[ds]?|opposition|unfavorable|against|vote\s+no|reject|do\s+not\s+(?:pass|support|approve))\b/i
    POSITION_HEADER_SUPPORT_PATTERN = /(?:\b(?:supports?|supporting|favorable(?:\s+with\s+amendments?)?|in\s+favor|vote\s+yes)\b|\Afor(?:\s+#{BILL_TARGET})?\z)/i

    SUBJECT_HEADER_OPPOSE_PATTERN = /(?:\b(?:unfavorable|vote\s+no|in\s+opposition|oppose\s+(?:(?:city\s+)?council\s+|senate\s+|house\s+)?(?:bill|hb|sb|cb)|do\s+not\s+(?:pass|support|approve))\b|\[oppose\]|-\s*oppose\s*\z)/i
    SUBJECT_HEADER_SUPPORT_PATTERN = /(?:\b(?:favorable(?:\s+with\s+amendments?)?|in\s+favor|vote\s+yes|in\s+support|support\s+(?:of|for)\s+(?:(?:city\s+)?council\s+|senate\s+|house\s+)?(?:bill|hb|sb|cb))\b|\[support\]|-\s*support\s*\z)/i

    NEGATED_PREFIX = /(?<!\bnot\s)(?<!\bnever\s)(?<!\bdon't\s)(?<!\bdon’t\s)(?<!\bdo\snot\s)(?<!\bcannot\s)(?<!\bcan't\s)(?<!\bcan’t\s)(?<!\bunable\sto\s)(?<!\brefuse\sto\s)/i

    OPPOSE_PATTERNS = [
      /\bvote\s+no\b/i,
      /\bvot(?:e|ing)\s+against\b/i,
      /\bunfavorable\s+report\b/i,
      /\breport\s+unfavorably\b/i,
      /\btestimony\s+in\s+(?:strong\s+)?opposition\b/i,
      /\b(?:do\s+not|don['’]t|must\s+not|should\s+not|cannot|can['’]t)\s+(?:pass|support|approve|vote\s+for|advance|enact|adopt)\b/i,
      /\b(?:urge|ask|request|call\s+on|implore)\s+(?:you|the\s+committee|the\s+(?:city\s+)?council|(?:council\s*)?members)(?:\s+not\s+to\s+(?:pass|support|approve|advance)|\s+to\s+(?:oppose|reject|defeat|vote\s+against|vote\s+no|table|withdraw))\b/i,
      /#{NEGATED_PREFIX}\b(?:(?:i|we)\s+(?:strongly\s+|firmly\s+|wholeheartedly\s+|respectfully\s+|vehemently\s+)?oppose|oppose\s+#{BILL_TARGET})/i,
      /\b(?:writing|write|testifying|testify|speaking|speak|submit(?:ting)?\s+testimony|here)\s+(?:today\s+)?(?:in\s+(?:strong\s+)?opposition|to\s+(?:strongly\s+|firmly\s+|respectfully\s+)?oppose)\b/i,
      /\bin\s+(?:strong\s+)?opposition\s+to\b/i,
      /\b(?:please\s+)?(?:reject|defeat)\s+#{BILL_TARGET}/i
    ].freeze

    SUPPORT_PATTERNS = [
      /\bvote\s+yes\b/i,
      /#{NEGATED_PREFIX}\bvot(?:e|ing)\s+(?:in\s+favor|for\s+#{BILL_TARGET})/i,
      /#{NEGATED_PREFIX}\bfavorable(?:\s+with\s+amendments?)?\s+report\b/i,
      /#{NEGATED_PREFIX}\breport\s+favorably\b/i,
      /\btestimony\s+in\s+(?:strong\s+)?support\b/i,
      /#{NEGATED_PREFIX}\b(?:urge|ask|request|call\s+on|implore)\s+(?:you|the\s+committee|the\s+(?:city\s+)?council|(?:council\s*)?members)\s+to\s+(?:pass|support|approve|enact|adopt|advance|vote\s+for|vote\s+yes)\b/i,
      /#{NEGATED_PREFIX}\b(?:(?:i|we)\s+(?:strongly\s+|firmly\s+|wholeheartedly\s+|respectfully\s+|fully\s+)?support\s+(?:the\s+\w+(?:\s+\w+){0,3}\s+in\s+)?#{BILL_TARGET}|(?:strongly|firmly|wholeheartedly|respectfully|fully)\s+support\s+(?:the\s+\w+(?:\s+\w+){0,3}\s+in\s+)?#{BILL_TARGET})/i,
      /#{NEGATED_PREFIX}\b(?:writing|write|testifying|testify|speaking|speak|submit(?:ting)?\s+testimony|here)\s+(?:today\s+)?(?:in\s+(?:strong\s+)?support|to\s+(?:strongly\s+|firmly\s+|respectfully\s+)?(?:urge\s+you\s+to\s+)?support)\b/i,
      /#{NEGATED_PREFIX}\bin\s+(?:strong\s+)?support\s+of\s+#{BILL_TARGET}/i,
      /#{NEGATED_PREFIX}\bplease\s+(?:pass|support|approve|enact|adopt|advance)\s+#{BILL_TARGET}/i
    ].freeze

    def self.classify(raw_text)
      text = Sway::Utf8.scrub(raw_text.to_s).strip
      return nil if text.empty?

      header_stance = classify_headers(text)

      stripped = Testimony::ExtractedText.strip_recipient_headers(
        Testimony::ExtractedText.strip_envelope(text.lstrip)
      ).strip
      body = (stripped.presence || text).gsub(/\s+/, " ").strip

      oppose_body = OPPOSE_PATTERNS.any? { |pattern| body.match?(pattern) }
      support_body = SUPPORT_PATTERNS.any? { |pattern| body.match?(pattern) }

      if oppose_body && !support_body
        return nil if header_stance == "support"

        "oppose"
      elsif support_body && !oppose_body
        return nil if header_stance == "oppose"

        "support"
      elsif !oppose_body && !support_body
        header_stance
      end
    end

    def self.classify_headers(text)
      oppose_header = false
      support_header = false

      text.each_line.first(15).each do |line|
        stripped_line = line.chomp
        if (pos_match = stripped_line.match(POSITION_HEADER_LINE_PATTERN))
          value = pos_match[1].to_s.gsub(/\s+/, " ").strip
          has_oppose = value.match?(POSITION_HEADER_OPPOSE_PATTERN)
          has_support = value.match?(POSITION_HEADER_SUPPORT_PATTERN) && !value.match?(/\b(?:not|never|don['’]t|do\s+not|cannot|can['’]t)\s+(?:pass\s+or\s+)?support\b/i)
        elsif (subj_match = stripped_line.match(SUBJECT_HEADER_LINE_PATTERN))
          value = subj_match[1].to_s.gsub(/\s+/, " ").strip
          has_oppose = value.match?(SUBJECT_HEADER_OPPOSE_PATTERN)
          has_support = value.match?(SUBJECT_HEADER_SUPPORT_PATTERN) && !value.match?(/\b(?:not|never|don['’]t|do\s+not|cannot|can['’]t)\s+(?:pass\s+or\s+)?support\b/i)
        else
          next
        end

        oppose_header ||= has_oppose
        support_header ||= has_support
      end

      return "oppose" if oppose_header && !support_header
      return "support" if support_header && !oppose_header

      nil
    end
    private_class_method :classify_headers
  end
end
