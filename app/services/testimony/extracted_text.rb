# frozen_string_literal: true

module Testimony
  # @lat: [[extracted-text-phrase-matching#Why a literal comparison fails]]
  module ExtractedText
    # @lat: [[extracted-text-phrase-matching#Stripping the mail envelope by field, not by block]]
    ENVELOPE_FIELD_NAMES = %w[From Sent Date To Cc Bcc Subject Reply-To Importance Attachments].freeze
    RECIPIENT_HEADER_NAMES = %w[To Cc Bcc].freeze

    RECIPIENT_CONTINUATION_LINE = /([^\s<>,@]+@[^\s<>,@]+|<[^>]+>|;|\(City\s+Council\))/i
    BODY_OPENING = /\A(dear\b|to\s+the\s+(?:council|honorable|committee)|honorable\b|members\s+of\b|hello\b|good\s+(morning|afternoon|evening)|caution:|reminder:|report\s+any|report\s+phishing|-{3,}|_{3,})/i

    # @lat: [[extracted-text-phrase-matching#Telling a real letter's header from a forwarded one]]
    FORWARD_OR_REPLY_LINE_MARKERS = [
      /\A-{2,}\s*Original\s+Message\s*-{2,}\z/i,
      /\A-{2,}\s*Forwarded\s+message\s*-{2,}\z/i,
      /\ABegin\s+forwarded\s+message:\z/i,
      /\A_{4,}\z/
    ].freeze

    QUOTE_OPENING_MARKER = /\AOn\s.+\bwrote:\z/i

    # @lat: [[testimony-letters#Attachment boundaries and the five-page constituent ceiling]]
    MAX_CONSTITUENT_PAGES = 5
    TRAILING_PRINT_HEADER_MAX_CHARS = 80
    TRAILING_PRINT_HEADER_MAX_LINES = 3

    ZERO_WIDTH_CHAR_PATTERN = /[\u200b\u200c\u200d\ufeff]/
    LINE_SEPARATOR_PATTERN = /\r\n|\r|[\u2028\u2029]/
    STANDALONE_PAGE_NUMBER_LINE = /\A[ \t]*\d+[ \t]*\z/
    TERMINAL_SENTENCE_PUNCTUATION = /[.!?:"”')\]]\z/
    LIST_ITEM_LINE_PATTERN = /\A(?:[•●▪◦*]|-(?=\s)|\d+[.)]|[a-zA-Z]\))\s+/
    METADATA_HEADER_LINE_PATTERN = /\A(?:(?:TESTIMONY|POSITION|STANCE|SUBJECT|RE|BILL|TO|FROM|DATE)[ \t]*:|(?:(?-i:[TW])RITTEN[ \t]+)?(?-i:T)ESTIMONY[ \t]+(?:IN[ \t]+(?:SUPPORT|OPPOSITION)|ON|FOR|AGAINST|TO)\b)/i
    ALL_CAPS_HEADING_LINE_PATTERN = /\A(?=.*[A-Z]{2})[A-Z0-9\s#&',.\-–—:()\/]{4,}\z/
    OPENING_SALUTATION_LINE_PATTERN = /\A(?:dear|to\s+the\s+(?:honorable|city\s+council|council|committee|chair|members|mayor)|honorable|the\s+honorable|chair(?:man|woman|person)?|council\s*(?:president|man|woman|member)|mayor|members\s+of|hello|good\s+(?:morning|afternoon|evening)|greetings)\b/i
    CLOSING_SIGNOFF_LINE_PATTERN = /\A(?:(?:sincerely|respectfully(?:\s+submitted)?|best(?:\s+regards|\s+wishes)?|warm\s+regards|kind\s+regards|regards|cordially|in\s+solidarity|yours\s+truly)[,!.:]?|thank\s+you(?:[,!.:]?|\s+for\s+(?:your\s+)?(?:time|consideration|attention|service|leadership)(?:\s+and\s+(?:time|consideration|attention|service))?[,!.:]?))\z/i
    MAX_FIRST_LINE_SALUTATION_CHARS = 45

    class << self
      def phrase_source(phrase)
        phrase.to_s.strip.split(/\s+/).map { |word| Regexp.escape(word) }.join('\s+')
      end

      def phrase_pattern(phrase)
        Regexp.new(phrase_source(phrase))
      end

      # @lat: [[extracted-text-phrase-matching#The two header-line helpers]]
      def header_line_pattern(phrase)
        /^#{phrase_source(phrase)}[ \t]*/
      end

      # @lat: [[extracted-text-phrase-matching#The two header-line helpers]]
      def header_line?(text, phrase)
        match = header_line_pattern(phrase).match(text.to_s)
        !match.nil? && match.begin(0) == 0
      end

      def starts_with_from_header?(text)
        lines = text.to_s.sub(/\A\f+/, "").split("\n")
        return false if lines.empty?

        idx = leading_envelope_start_index(lines)
        header_line?(lines[idx].to_s, "From:")
      end

      def envelope_field_line?(line)
        ENVELOPE_FIELD_NAMES.any? { |name| header_line?(line, "#{name}:") }
      end

      # @lat: [[extracted-text-phrase-matching#Handling multiline envelope headers and forwarded wrappers]]
      def envelope_continuation_line?(line, current_field, field_line_was_empty, previous_ended_with_separator = false)
        trimmed = line.strip
        return false if trimmed.empty?
        return false if envelope_field_line?(line)
        return false if BODY_OPENING.match?(trimmed)

        if field_line_was_empty
          true
        elsif %w[To Cc Bcc From].include?(current_field)
          RECIPIENT_CONTINUATION_LINE.match?(line) ||
            (previous_ended_with_separator && !trimmed.end_with?(".", "!", "?"))
        else
          false
        end
      end

      # @lat: [[extracted-text-phrase-matching#Stripping the mail envelope by field, not by block]]
      def strip_envelope(text)
        lines = strip_edge_print_header_stubs(text.to_s).sub(/\A\f+/, "").split("\n")
        index = leading_envelope_start_index(lines)
        in_envelope = false
        current_field = nil
        field_empty = false
        prev_sep = false

        while index < lines.length
          line = lines[index]
          trimmed = line.strip

          if envelope_field_line?(line)
            in_envelope = true
            current_field = ENVELOPE_FIELD_NAMES.find { |name| header_line?(line, "#{name}:") }
            value_part = line.sub(header_line_pattern("#{current_field}:"), "").strip
            field_empty = value_part.empty?
            prev_sep = value_part.end_with?(",", ";")
            index += 1
          elsif in_envelope && line.match?(/\A[ \t]/)
            field_empty = false
            prev_sep = trimmed.end_with?(",", ";")
            index += 1
          elsif in_envelope && envelope_continuation_line?(line, current_field, field_empty, prev_sep)
            field_empty = false
            prev_sep = trimmed.end_with?(",", ";")
            index += 1
          elsif in_envelope && trimmed.empty?
            lookahead = index
            lookahead += 1 while lookahead < lines.length && lines[lookahead].strip.empty?
            if lookahead < lines.length && envelope_field_line?(lines[lookahead])
              index = lookahead
            else
              index = lookahead
              break
            end
          else
            break
          end
        end

        lines[index..].to_a.join("\n")
      end

      # @lat: [[extracted-text-phrase-matching#Handling multiline envelope headers and forwarded wrappers]]
      def strip_recipient_headers(text)
        lines = text.to_s.split("\n", -1)
        index = 0
        output_lines = []
        in_envelope = false
        in_recipient_field = false
        current_field = nil
        field_empty = false
        prev_sep = false

        while index < lines.length
          line = lines[index]
          trimmed = line.strip

          if recipient_header_start?(lines, index, in_envelope)
            current_field = RECIPIENT_HEADER_NAMES.find { |name| header_line?(line, "#{name}:") }
            value_part = line.sub(header_line_pattern("#{current_field}:"), "").strip
            in_envelope = true
            in_recipient_field = true
            field_empty = value_part.empty?
            prev_sep = value_part.end_with?(",", ";")
          elsif in_recipient_field && (line.match?(/\A[ \t]/) || envelope_continuation_line?(line, current_field, field_empty, prev_sep))
            field_empty = false
            prev_sep = trimmed.end_with?(",", ";")
          elsif envelope_field_line?(line)
            current_field = ENVELOPE_FIELD_NAMES.find { |name| header_line?(line, "#{name}:") }
            value_part = line.sub(header_line_pattern("#{current_field}:"), "").strip
            in_envelope = true
            in_recipient_field = false
            field_empty = value_part.empty?
            prev_sep = value_part.end_with?(",", ";")
            output_lines << line
          elsif in_envelope && (line.match?(/\A[ \t]/) || envelope_continuation_line?(line, current_field, field_empty, prev_sep))
            in_recipient_field = false
            field_empty = false
            prev_sep = trimmed.end_with?(",", ";")
            output_lines << line
          elsif in_envelope && trimmed.empty?
            in_recipient_field = false
            field_empty = false
            prev_sep = false
            lookahead = index + 1
            lookahead += 1 while lookahead < lines.length && lines[lookahead].strip.empty?
            in_envelope = lookahead < lines.length && envelope_field_line?(lines[lookahead])
            output_lines << line
          else
            in_envelope = false
            in_recipient_field = false
            current_field = nil
            field_empty = false
            prev_sep = false
            output_lines << line
          end
          index += 1
        end

        output_lines.join("\n")
      end

      # @lat: [[extracted-text-phrase-matching#Telling a real letter's header from a forwarded one]]
      def forward_or_reply_marker?(lines)
        stripped = Array(lines).map { |line| line.to_s.strip }
        return true if stripped.any? { |line| FORWARD_OR_REPLY_LINE_MARKERS.any? { |pattern| pattern.match?(line) } }
        return true if stripped.any? { |line| QUOTE_OPENING_MARKER.match?(line) }

        stripped.each_cons(2).any? { |first, second| QUOTE_OPENING_MARKER.match?("#{first} #{second}") }
      end

      # @lat: [[testimony-letters#Attachment boundaries and the five-page constituent ceiling]]
      def print_header_stub?(text)
        stripped = text.to_s.strip
        return true if stripped.empty?
        return false if header_line?(stripped, "From:")
        return false if stripped.lines.any? { |line| BODY_OPENING.match?(line.strip) }
        return false if /\b(?:support|oppose|urge|vote|pass|reject|favor|against|favorable|unfavorable|bill|ordinance|resolution|testimony)\b/i.match?(stripped)

        stripped.length < TRAILING_PRINT_HEADER_MAX_CHARS &&
          stripped.lines.count { |line| !line.strip.empty? } <= TRAILING_PRINT_HEADER_MAX_LINES &&
          !/[.!?]/.match?(stripped.gsub(/\b[A-Z]\.(?=\s)/, ""))
      end

      # @lat: [[testimony-letters#Attachment boundaries and the five-page constituent ceiling]]
      def clerk_print_header_stub?(text)
        cleaned = text.to_s
        (/\A[ \t\n]*\d+(?:[ \t]*\n|\z)/.match?(cleaned) || /\((?:City[ \t]+Council|Mayor|Comptroller)\)/i.match?(cleaned)) &&
          print_header_stub?(cleaned)
      end

      # @lat: [[testimony-letters#Attachment boundaries and the five-page constituent ceiling]]
      def effective_page_count(text)
        text.to_s.split("\f", -1).count { |page| !print_header_stub?(page) }
      end

      # @lat: [[testimony-letters#Attachment boundaries and the five-page constituent ceiling]]
      def over_constituent_page_limit?(text)
        effective_page_count(text) > MAX_CONSTITUENT_PAGES
      end

      # @lat: [[testimony-letters#Selecting browsable constituent letters]]
      def unwrap_body_paragraphs(text)
        normalized = text.to_s
          .gsub(ZERO_WIDTH_CHAR_PATTERN, "")
          .gsub(LINE_SEPARATOR_PATTERN, "\n")
        return "" if normalized.strip.empty?

        joined_pages = unwrap_page_breaks(normalized)
        collapsed = collapse_artificial_double_spacing(joined_pages)
        paragraphs = collapsed.split(/\n(?:[ \t]*\n)+/)

        first_paragraph = true
        unwrapped_paragraphs = paragraphs.filter_map do |paragraph|
          lines = paragraph.split("\n").map { |line| line.strip.gsub(/[ \t]{2,}/, " ") }.reject(&:empty?)
          next if lines.empty?

          unwrapped = unwrap_paragraph_lines(lines, first_paragraph: first_paragraph)
          first_paragraph = false
          unwrapped
        end

        unwrapped_paragraphs.join("\n\n")
      end

      private

      def unwrap_page_breaks(text)
        return text unless text.include?("\f")

        pages = text.split("\f", -1).filter_map do |page|
          next if page.strip.empty? || clerk_print_header_stub?(page)

          page_lines = page.split("\n")
          page_lines.shift while page_lines.first && STANDALONE_PAGE_NUMBER_LINE.match?(page_lines.first)
          page_lines.pop while page_lines.last && STANDALONE_PAGE_NUMBER_LINE.match?(page_lines.last)
          cleaned_page = page_lines.join("\n")
          cleaned_page unless cleaned_page.strip.empty?
        end

        pages.join("\n")
      end

      def collapse_artificial_double_spacing(text)
        chunks = text.split(/(\n(?:[ \t]*\n)+)/)
        return text if chunks.length < 3

        result = +chunks[0].to_s
        idx = 1
        while idx < chunks.length
          sep = chunks[idx].to_s
          next_chunk = chunks[idx + 1].to_s
          single_blank_line = sep.count("\n") == 2
          prev_line = result.split("\n", -1).last.to_s.strip
          next_line = next_chunk.split("\n", -1).first.to_s.strip
          first_line_of_text = result.lines.count { |line| !line.strip.empty? } <= 1

          if single_blank_line && artificial_blank_line_between?(prev_line, next_line, first_line_of_text: first_line_of_text)
            result << "\n" << next_chunk
          else
            result << sep << next_chunk
          end
          idx += 2
        end

        result
      end

      def artificial_blank_line_between?(prev_line, next_line, first_line_of_text: false)
        return false if prev_line.empty? || next_line.empty?
        return false if TERMINAL_SENTENCE_PUNCTUATION.match?(prev_line)
        return false if LIST_ITEM_LINE_PATTERN.match?(prev_line) || LIST_ITEM_LINE_PATTERN.match?(next_line)
        return false if metadata_or_heading_line?(prev_line) || metadata_or_heading_line?(next_line)
        return false if OPENING_SALUTATION_LINE_PATTERN.match?(prev_line) && (first_line_of_text || /[:,]\z/.match?(prev_line))
        return false if CLOSING_SIGNOFF_LINE_PATTERN.match?(prev_line) || CLOSING_SIGNOFF_LINE_PATTERN.match?(next_line)

        /\A[a-z0-9]/.match?(next_line) || /[,-]\z/.match?(prev_line) ||
          /\b(?:and|or|to|of|in|for|with|on|at|by|from|that|which|who|whom|whose|as|into|like|through|after|over|between|out|against|during|without|before|under|around|among|the|a|an|is|are|was|were|be|been|being|have|has|had|do|does|did|will|would|shall|should|can|could|may|might|must|am|not|no|nor|so|yet|both|either|neither|very|more|most)\z/i.match?(prev_line)
      end

      def unwrap_paragraph_lines(lines, first_paragraph:)
        output = +lines.first.to_s
        prev_line = lines.first.to_s
        in_signoff_block = CLOSING_SIGNOFF_LINE_PATTERN.match?(prev_line)

        lines.drop(1).each_with_index do |curr_line, idx|
          is_very_first_line = first_paragraph && idx.zero?
          if keep_line_break_between?(prev_line, curr_line, is_very_first_line: is_very_first_line, in_signoff_block: in_signoff_block)
            output << "\n" << curr_line
            in_signoff_block = true if closing_signoff_transition?(prev_line, curr_line)
          elsif /[a-z]-\z/.match?(prev_line) && /\A[a-z]/.match?(curr_line)
            output << curr_line
          else
            output << " " << curr_line
          end
          prev_line = curr_line
        end

        output
      end

      def keep_line_break_between?(prev_line, curr_line, is_very_first_line:, in_signoff_block:)
        return true if in_signoff_block
        return true if LIST_ITEM_LINE_PATTERN.match?(curr_line)
        return true if metadata_or_heading_line?(prev_line) || metadata_or_heading_line?(curr_line)
        return true if closing_signoff_transition?(prev_line, curr_line)
        return true if opening_salutation_line?(prev_line, curr_line, is_very_first_line: is_very_first_line)

        false
      end

      def closing_signoff_transition?(prev_line, curr_line)
        CLOSING_SIGNOFF_LINE_PATTERN.match?(curr_line) && (/[.!?:;]\z/.match?(prev_line) || prev_line.length <= 60)
      end

      def metadata_or_heading_line?(line)
        return false if line.length > 90 || /[.!]\z/.match?(line) || /\A[a-z]/.match?(line)

        METADATA_HEADER_LINE_PATTERN.match?(line) || ALL_CAPS_HEADING_LINE_PATTERN.match?(line)
      end

      def opening_salutation_line?(prev_line, curr_line, is_very_first_line:)
        return false unless is_very_first_line
        return true if OPENING_SALUTATION_LINE_PATTERN.match?(prev_line) && prev_line.length <= 80 && !/[.!]\z/.match?(prev_line)

        prev_line.length <= MAX_FIRST_LINE_SALUTATION_CHARS &&
          !/[.!?]\z/.match?(prev_line) &&
          /\A[A-Z]/.match?(curr_line)
      end

      def strip_edge_print_header_stubs(text)
        return text unless text.include?("\f")

        pages = text.split("\f", -1)
        pages.shift while pages.length > 1 && (pages.first.to_s.strip.empty? || clerk_print_header_stub?(pages.first))
        pages.pop while pages.length > 1 && (pages.last.to_s.strip.empty? || clerk_print_header_stub?(pages.last))
        pages.join("\f")
      end

      def leading_envelope_start_index(lines)
        scan_idx = 0
        while scan_idx < lines.length
          trimmed = lines[scan_idx].to_s.strip
          if trimmed.empty? ||
              FORWARD_OR_REPLY_LINE_MARKERS.any? { |pat| pat.match?(trimmed) } ||
              QUOTE_OPENING_MARKER.match?(trimmed) ||
              /\A\d+\z/.match?(trimmed) ||
              /\((?:City[ \t]+Council|Mayor|Comptroller)\)/i.match?(trimmed)
            scan_idx += 1
          elsif scan_idx + 1 < lines.length &&
              QUOTE_OPENING_MARKER.match?("#{trimmed} #{lines[scan_idx + 1].to_s.strip}")
            scan_idx += 2
          else
            break
          end
        end

        (scan_idx < lines.length && envelope_field_line?(lines[scan_idx].to_s)) ? scan_idx : 0
      end

      def recipient_header_start?(lines, index, in_envelope)
        line = lines[index].to_s
        field = RECIPIENT_HEADER_NAMES.find { |name| header_line?(line, "#{name}:") }
        return false unless field
        return true if in_envelope

        value_part = line.sub(header_line_pattern("#{field}:"), "").strip
        return true if RECIPIENT_CONTINUATION_LINE.match?(value_part)

        next_line = lines[index + 1].to_s.strip
        envelope_field_line?(next_line) || RECIPIENT_CONTINUATION_LINE.match?(next_line)
      end
    end
  end
end
