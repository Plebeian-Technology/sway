# frozen_string_literal: true

module Testimony
  # @lat: [[extracted-text-phrase-matching#Handling multiline envelope headers and forwarded wrappers]]
  class BoilerplateRemover
    CITY_IT_BANNER = <<~TXT.chomp
      CAUTION:  This email originated from outside of Baltimore City IT Network Systems.
      Reminder:  DO NOT click links or open attachments unless you recognize the sender and know that the content is safe.
      Report any suspicious activities using the Report Phishing Email Button, or by emailing to Phishing@baltimorecity.gov
    TXT

    LETTER_MARKER = Testimony::ExtractedText.header_line_pattern("From:")
    MARKER_LOOKBACK_LINES = 4
    MEMO_HEADER_LINE_PATTERN = /\A(?:memorandum\b|memo\b|(?:to|date|re|subject)[;:]\s*\S|(?:written[ \t]+)?testimony[ \t]+(?:in[ \t]+(?:support|opposition)|on|for|against|to)\b)/i
    FORWARD_SUBJECT_PATTERN = /^[ \t]*Subject:[ \t]*\n?[ \t]*(?:Fw|FW|Fwd|FWD):/i
    MAX_FORWARD_WRAPPER_BODY_CHARS = 500
    MAX_INTERNAL_ROUTING_NOTE_CHARS = 240
    MAX_INTERNAL_ROUTING_NOTE_LINES = 4

    INTERNAL_ROUTING_NOTE_PATTERN = %r{
      \b(?:
        please[ \t]+(?:add|include|attach|place|file|upload|log)\b[^\n]{0,60}\b(?:to|in)[ \t]+the[ \t]+(?:bill[ \t]+file|folder|packet)\b
        |
        (?:good[ \t]+(?:morning|afternoon|evening)|hi|hello)\b[^\n]{0,40}\bplease[ \t]+(?:add|include|attach|see[ \t]+attached)\b
        |
        adding[ \t]+to[ \t]+the[ \t]+(?:bill[ \t]+file|folder|packet)\b
        |
        (?:fyi|for[ \t]+your[ \t]+information)\b[^\n]{0,40}\b(?:bill[ \t]+file|attached)\b
      )
      |
      \A\s*(?:please[ \t]+)?see[ \t]+attached(?:[ \t]+testimony)?[.!]?\s*\z
      |
      \A\s*attached[ \t]+(?:please[ \t]+find|is)[ \t]+(?:the[ \t]+)?(?:testimony|letter)[ \t]+for[ \t]+the[ \t]+bill[ \t]+file[.!]?\s*\z
    }mix

    TESTIMONY_PROSE_PATTERN = %r{
      ^[ \t]*(?:dear|to[ \t]+the[ \t]+(?:honorable|council|committee)|honorable|members[ \t]+of)\b
      |
      \b(?:I[ \t]+am[ \t]+writing|I[ \t]+write|we[ \t]+are[ \t]+writing|I[ \t]+(?:strongly[ \t]+)?(?:support|oppose|urge|ask|believe|think|live|own|work)|we[ \t]+(?:strongly[ \t]+)?(?:support|oppose|urge|ask|believe|think|live|own|work)|please[ \t]+(?:vote|support|oppose|pass|reject|amend|consider)|vote[ \t]+(?:yes|no|for|against)|in[ \t]+(?:strong[ \t]+)?(?:support|opposition)[ \t]+of|as[ \t]+a[ \t]+(?:resident|homeowner|voter|constituent|taxpayer|business[ \t]+owner)|(?:this|the)[ \t]+(?:bill|ordinance|legislation|resolution)|(?:my|our)[ \t]+(?:neighborhood|community|block|street|family|business)|enact|approve|amend)\b
    }mix

    FOOTER_INNER_LINE = /(?![ \t]*(?:From:|Sent:|Date:|To:|Cc:|Bcc:|Subject:|Dear\b))[ \t]*\S[^\n]*\n/i

    MUNICIPAL_OFFICE_FOOTER_PATTERN = %r{
      ^[ \t]*(?:
        Office[ \t]+of\b[^\n]*
        |
        Council(?:man|woman|member)\b[^\n]*
        |
        (?![ \t]*(?:The[ \t]+)?Honorable\b)[A-Z][a-zA-Z ,.'-]+\n[ \t]*(?:Council(?:man|woman|member)|President|Vice[ \t]+President)\b[^\n]*
      )\n
      (?:#{FOOTER_INNER_LINE}){0,5}
      (?:
        [ \t]*100[ \t]+(?:N\.?[ \t]*)?Holliday[ \t]+St(?:reet)?[^\n]*\n
        (?:#{FOOTER_INNER_LINE}){0,4}
        [ \t]*Baltimore,?[ \t]*MD[ \t]*21202[^\n]*\n?
        (?:[ \t]*(?:Office|Phone|Tel|Cell|Fax|Direct)?:?[ \t]*\(?410\)?[ \t]*\d{3}-\d{4}[^\n]*\n?)?
        |
        [ \t]*(?:Office|Phone|Tel|Cell|Fax|Direct)?:?[ \t]*\(?410\)?[ \t]*396-\d{4}[^\n]*\n?
      )
      (?:[ \t]*Request[ \t]+(?:the[ \t]+)?Council\b[^\n]*here[^\n]*\n?)?
    }mix

    REQUEST_COUNCIL_MEETING_PATTERN = /^[ \t]*Request[ \t]+(?:the[ \t]+)?Council[^\n]*\bhere[ \t]*$/i

    DEVICE_FOOTER_PATTERNS = [
      /^[ \t]*Sent[ \t]+from[ \t]+my[ \t]+(?:iPhone|iPad|Galaxy|Android|mobile[ \t]+device)\b[ \t]*$/i,
      /^[ \t]*Get[ \t]+Outlook[ \t]+for[ \t]+(?:iOS|Android)\b[ \t]*$/i,
      /^[ \t]*Sent[ \t]+from[ \t]+Mail[ \t]+for[ \t]+Windows\b[ \t]*$/i
    ].freeze

    CONFIDENTIALITY_DISCLAIMER_PATTERNS = [
      %r{^[ \t]*(?:CONFIDENTIALITY[ \t]+(?:NOTICE|WARNING)|PRIVILEGED[ \t]+AND[ \t]+CONFIDENTIAL|DISCLAIMER):?[ \t]*\n(?:#{FOOTER_INNER_LINE}){1,8}}i,
      %r{^[ \t]*This[ \t]+(?:e-?mail|message|transmission)[ \t]+(?:and[ \t]+any[ \t]+attachments[ \t]+)?is[ \t]+(?:intended|confidential|for[ \t]+the[ \t]+sole[ \t]+use[ \t]+of)\b[^\n]*(?:\n(?![ \t]*(?:From:|Sent:|Date:|To:|Cc:|Bcc:|Subject:|Dear\b))[ \t]*\S[^\n]*){0,6}?(?:immediately[ \t]+notify|delete[ \t]+(?:this|all)|destroy[ \t]+all|in[ \t]+error)\b[^\n]*\n?}i
    ].freeze

    # @lat: [[testimony-attachment-rules#Testimony attachment rules#Every fixed phrase matches through the extracted-text helper]]
    PATTERNS = [
      Testimony::ExtractedText.phrase_pattern(CITY_IT_BANNER),
      MUNICIPAL_OFFICE_FOOTER_PATTERN,
      REQUEST_COUNCIL_MEETING_PATTERN,
      *DEVICE_FOOTER_PATTERNS,
      *CONFIDENTIALITY_DISCLAIMER_PATTERNS
    ].freeze

    Result = Data.define(:text, :characters_removed, :occurrences)

    class << self
      def call(text)
        cleaned = text.to_s
        characters_removed = 0
        occurrences = 0

        PATTERNS.each do |pattern|
          cleaned = cleaned.gsub(pattern) do |match|
            characters_removed += match.length
            occurrences += 1
            ""
          end
        end

        cleaned, wrapper_chars, wrapper_count = strip_forward_wrappers(cleaned)
        characters_removed += wrapper_chars
        occurrences += wrapper_count

        Result.new(text: cleaned, characters_removed: characters_removed, occurrences: occurrences)
      end

      # @lat: [[extracted-text-phrase-matching#Handling multiline envelope headers and forwarded wrappers]]
      def forward_wrapper?(seg)
        return false unless Testimony::ExtractedText.starts_with_from_header?(seg)
        return false if seg.include?("\f")

        body = Testimony::ExtractedText.strip_envelope(seg.lstrip)
        body_lines = body.split("\n").map(&:strip).reject(&:empty?)
        return false if body_lines.any? { |line| MEMO_HEADER_LINE_PATTERN.match?(line) }

        idx = 0
        while idx < body_lines.length
          if idx + 1 < body_lines.length &&
              Testimony::ExtractedText::QUOTE_OPENING_MARKER.match?("#{body_lines[idx]} #{body_lines[idx + 1]}")
            body_lines.slice!(idx, 2)
          else
            idx += 1
          end
        end

        body_lines.reject! do |line|
          Testimony::ExtractedText::FORWARD_OR_REPLY_LINE_MARKERS.any? { |pat| pat.match?(line) } ||
            Testimony::ExtractedText::QUOTE_OPENING_MARKER.match?(line)
        end
        cleaned_body = body_lines.join("\n")
        return true if cleaned_body.empty?
        if (FORWARD_SUBJECT_PATTERN.match?(seg) ||
            Testimony::ExtractedText.forward_or_reply_marker?(seg.lines) ||
            /\b(?:baltimorecity\.gov|baltimorecouncil\.com|maryland\.gov|mgaleg\.maryland\.gov|state\.md\.us)\b/i.match?(seg[0, 400].to_s)) &&
            internal_routing_note?(cleaned_body)
          return true
        end

        if FORWARD_SUBJECT_PATTERN.match?(seg) &&
            cleaned_body.length < MAX_FORWARD_WRAPPER_BODY_CHARS &&
            !TESTIMONY_PROSE_PATTERN.match?(cleaned_body)
          return true
        end

        false
      end

      def internal_routing_note?(text)
        cleaned = text.to_s.strip
        return false if cleaned.empty? || cleaned.length > MAX_INTERNAL_ROUTING_NOTE_CHARS
        return false if cleaned.lines.count { |line| !line.strip.empty? } > MAX_INTERNAL_ROUTING_NOTE_LINES
        return false unless INTERNAL_ROUTING_NOTE_PATTERN.match?(cleaned)

        !/\b(?:support|supports|supporting|oppose|opposes|opposing|opposition|favorable|unfavorable|amend|amendment|amendments|urge|urges|approve|reject|pass|defeat|vote[ \t]+(?:yes|no|for|against)|on[ \t]+behalf[ \t]+of|dear[ \t]+(?:chair|council|committee|president|members|mayor)|as[ \t]+a[ \t]+(?:resident|homeowner|voter|constituent|taxpayer|business[ \t]+owner)|I[ \t]+(?:strongly[ \t]+)?(?:believe|think|live|own|work|ask|write|am[ \t]+writing)|we[ \t]+(?:strongly[ \t]+)?(?:believe|think|ask|write|are[ \t]+writing))\b/i.match?(cleaned)
      end

      # @lat: [[extracted-text-phrase-matching#Handling multiline envelope headers and forwarded wrappers]]
      def classify_segments(text)
        raw_offsets = raw_marker_starts(text)
        return [] if raw_offsets.empty?

        segments = [] #: Array[[Integer, Integer, bool]]
        first_marker = raw_offsets.first || 0
        current_start = first_marker

        if first_marker.positive? && !text[0...first_marker].to_s.strip.empty?
          if forward_or_reply_above?(text, first_marker)
            current_start = 0
          else
            segments << [0, first_marker, false]
          end
        end

        idx = 1
        while idx < raw_offsets.length
          candidate_end = raw_offsets.fetch(idx)
          seg = text[current_start...candidate_end].to_s

          if forward_wrapper?(seg)
            segments << [current_start, candidate_end, true]
            current_start = candidate_end
          elsif !forward_or_reply_above?(text, candidate_end)
            segments << [current_start, candidate_end, false]
            current_start = candidate_end
          end
          idx += 1
        end

        segments << [current_start, text.length, false]
        segments
      end

      private

      def strip_forward_wrappers(text)
        segments = classify_segments(text)
        wrappers = segments.select { |_start, _finish, is_wrapper| is_wrapper }
        return [text, 0, 0] if wrappers.empty?

        output = +""
        cursor = 0
        removed_chars = 0
        wrappers.each do |start, finish, _is_wrapper|
          output << text[cursor...start].to_s if start > cursor
          removed_chars += finish - start
          cursor = finish
        end
        output << text[cursor..].to_s if cursor < text.length

        [output, removed_chars, wrappers.length]
      end

      def raw_marker_starts(text)
        offsets = []
        # @lat: [[rbs-signatures#Why a provably-safe value still needs a guard]]
        text.scan(LETTER_MARKER) do
          match = Regexp.last_match
          next unless match

          start = match.begin(0)
          next unless start
          next if memo_header_above?(text, start)

          offsets << start
        end
        offsets
      end

      def forward_or_reply_above?(text, offset)
        return false if offset.zero?

        lines = text[0...offset].to_s.split("\n").map(&:strip).reject(&:empty?).last(MARKER_LOOKBACK_LINES).to_a
        Testimony::ExtractedText.forward_or_reply_marker?(lines)
      end

      # @lat: [[testimony-letters#Attachment boundaries and the five-page constituent ceiling]]
      def memo_header_above?(text, offset)
        return false unless offset.positive?
        return false if /\AFrom:[^\n]*\n[ \t]*Sent:/i.match?(text[offset, 200].to_s)

        current_page = text[0...offset].to_s.split("\f", -1).last.to_s
        return false if LETTER_MARKER.match?(current_page)

        page_lines = current_page.split("\n").map(&:strip).reject(&:empty?)
        lookback = page_lines.last(MARKER_LOOKBACK_LINES).to_a
        return true if lookback.any? { |line| /\A(?:memorandum\b|memo\b|(?:written[ \t]+)?testimony[ \t]+(?:in[ \t]+(?:support|opposition)|on|for|against|to)\b)/i.match?(line) }
        return true if lookback.count { |line| /\A(?:to|date|re|subject)[;:]\s*\S/i.match?(line) } >= 2
        if lookback.any? { |line| /\Ato[;:]\s*\S/i.match?(line) } &&
            /\AFrom:[^\n]*\n[ \t]*(?:date|re|subject)[;:]\s*\S/i.match?(text[offset, 200].to_s)
          return true
        end
        return false if page_lines.length > MARKER_LOOKBACK_LINES + 2

        lookback.any? { |line| MEMO_HEADER_LINE_PATTERN.match?(line) }
      end
    end
  end
end
